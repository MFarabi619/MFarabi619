#include "ssh_server.h"
#include "../shell/shell.h"

#include <Arduino.h>
#include <LittleFS.h>

#include "libssh_esp32.h"
#include <libssh/callbacks.h>
#include <libssh/libssh.h>
#include <libssh/server.h>

#include <microshell.h>
#include <sys/reent.h>
#include <string.h>

//------------------------------------------
//  Internal State
//------------------------------------------
static struct _reent reent_data_esp32;

static const char *ssh_user    = SSH_DEFAULT_USER;
static const char *ssh_password = SSH_DEFAULT_USER;
static const char *ssh_hostkey = SSH_DEFAULT_HOSTKEY;
static const int   ssh_port    = SSH_DEFAULT_PORT;

//------------------------------------------
//  Per-connection state
//------------------------------------------
static ssh_channel active_chan = NULL;
static volatile bool shell_requested = false;
static volatile bool session_alive = true;

//------------------------------------------
//  Ring buffer (SSH channel → MicroShell)
//------------------------------------------
#define SSH_RING_SIZE 512
static char ssh_ring[SSH_RING_SIZE];
static volatile int ssh_ring_head = 0;
static volatile int ssh_ring_tail = 0;

static void ssh_ring_reset(void) {
  ssh_ring_head = 0;
  ssh_ring_tail = 0;
}

static void ssh_ring_push(char c) {
  int next = (ssh_ring_head + 1) % SSH_RING_SIZE;
  if (next != ssh_ring_tail) {
    ssh_ring[ssh_ring_head] = c;
    ssh_ring_head = next;
  }
}

static int ssh_ring_pop(char *c) {
  if (ssh_ring_tail == ssh_ring_head) return 0;
  *c = ssh_ring[ssh_ring_tail];
  ssh_ring_tail = (ssh_ring_tail + 1) % SSH_RING_SIZE;
  return 1;
}

//------------------------------------------
//  MicroShell instance for SSH
//------------------------------------------
// Write buffer — accumulate output, flush in one SSH packet
#define SSH_WRITE_BUF_SIZE 1024
static char ssh_write_buf[SSH_WRITE_BUF_SIZE];
static int ssh_write_buf_pos = 0;

static void ssh_write_flush(void) {
  if (ssh_write_buf_pos > 0) {
    if (active_chan)
      ssh_channel_write(active_chan, ssh_write_buf, ssh_write_buf_pos);
    ssh_write_buf_pos = 0;  // always reset, even if channel is gone
  }
}

static int ssh_shell_read(struct ush_object *self, char *ch) {
  (void)self;
  return ssh_ring_pop(ch);
}

static int ssh_shell_write(struct ush_object *self, char ch) {
  (void)self;
  if (!active_chan) return 0;
  ssh_write_buf[ssh_write_buf_pos++] = ch;
  if (ssh_write_buf_pos >= SSH_WRITE_BUF_SIZE)
    ssh_write_flush();
  return 1;
}

static const struct ush_io_interface ssh_shell_io = {
  .read = ssh_shell_read,
  .write = ssh_shell_write,
};

static char ssh_shell_in_buf[SHELL_BUF_IN_SIZE];
static char ssh_shell_out_buf[SHELL_BUF_OUT_SIZE];
static struct ush_object ssh_ush;

static const struct ush_descriptor ssh_shell_desc = {
  .io = &ssh_shell_io,
  .input_buffer = ssh_shell_in_buf,
  .input_buffer_size = sizeof(ssh_shell_in_buf),
  .output_buffer = ssh_shell_out_buf,
  .output_buffer_size = sizeof(ssh_shell_out_buf),
  .path_max_length = SHELL_PATH_MAX_SIZE,
  .hostname = shell_get_hostname(),
};

static void ssh_shell_setup(void) {
  ssh_ring_reset();
  ssh_write_buf_pos = 0;
  shell_init_instance(&ssh_ush, &ssh_shell_desc);
}

//------------------------------------------
//  LibSSH Server Callbacks
//------------------------------------------
static int on_auth_password(ssh_session session, const char *user,
                            const char *password, void *userdata) {
  (void)session; (void)userdata;
  if (strcmp(user, ssh_user) == 0 && strcmp(password, ssh_password) == 0) {
    Serial.printf("[ssh] authenticated user: %s\n", user);
    return SSH_AUTH_SUCCESS;
  }
  return SSH_AUTH_DENIED;
}

static ssh_channel on_channel_open(ssh_session session, void *userdata) {
  (void)userdata;
  active_chan = ssh_channel_new(session);
  Serial.println("[ssh] channel opened");
  return active_chan;
}

//------------------------------------------
//  LibSSH Channel Callbacks
//------------------------------------------
static int on_channel_data(ssh_session session, ssh_channel channel,
                           void *data, uint32_t len, int is_stderr,
                           void *userdata) {
  (void)session; (void)channel; (void)is_stderr; (void)userdata;
  char *bytes = (char *)data;
  for (uint32_t i = 0; i < len; i++) {
    if (bytes[i] == '\x04') {  // Ctrl+D
      session_alive = false;
      return len;
    }
    ssh_ring_push(bytes[i]);
  }
  return len;
}

static int on_pty_request(ssh_session session, ssh_channel channel,
                          const char *term, int width, int height,
                          int pxwidth, int pxheight, void *userdata) {
  (void)session; (void)channel; (void)term;
  (void)pxwidth; (void)pxheight; (void)userdata;
  Serial.printf("[ssh] pty request: %dx%d\n", width, height);
  return 0;  // accept
}

static int on_shell_request(ssh_session session, ssh_channel channel,
                            void *userdata) {
  (void)session; (void)channel; (void)userdata;
  Serial.println("[ssh] shell requested");
  shell_requested = true;
  return 0;  // accept
}

static void on_channel_eof(ssh_session session, ssh_channel channel,
                           void *userdata) {
  (void)session; (void)channel; (void)userdata;
  session_alive = false;
}

static void on_channel_close(ssh_session session, ssh_channel channel,
                             void *userdata) {
  (void)session; (void)channel; (void)userdata;
  session_alive = false;
}

//------------------------------------------
//  SSH Host Key Generation
//------------------------------------------
static bool ssh_ensure_hostkey(void) {
  if (LittleFS.exists(ssh_hostkey)) {
    Serial.println("[ssh] host key found");
    return true;
  }

  Serial.println("[ssh] generating ed25519 host key...");
  ssh_key key = NULL;
  int rc = ssh_pki_generate(SSH_KEYTYPE_ED25519, 0, &key);
  if (rc != SSH_OK || key == NULL) {
    Serial.println("[ssh] key generation failed");
    return false;
  }

  rc = ssh_pki_export_privkey_file(key, NULL, NULL, NULL, ssh_hostkey);
  ssh_key_free(key);

  if (rc != SSH_OK) {
    Serial.printf("[ssh] failed to write key to %s\n", ssh_hostkey);
    return false;
  }

  Serial.printf("[ssh] host key saved to %s\n", ssh_hostkey);
  return true;
}

//------------------------------------------
//  SSH Server Task
//------------------------------------------
static void ssh_server_task(void *pvParameters) {
  (void)pvParameters;
  _REENT_INIT_PTR((&reent_data_esp32));

  libssh_begin();

  if (!ssh_ensure_hostkey()) {
    Serial.println("[ssh] cannot start without host key");
    vTaskDelete(NULL);
    return;
  }

  // Bind once, accept in loop
  ssh_bind sshbind = ssh_bind_new();
  ssh_bind_options_set(sshbind, SSH_BIND_OPTIONS_BINDPORT, &ssh_port);
  ssh_bind_options_set(sshbind, SSH_BIND_OPTIONS_HOSTKEY, ssh_hostkey);

  if (ssh_bind_listen(sshbind) < 0) {
    Serial.printf("[ssh] bind error: %s\n", ssh_get_error(sshbind));
    ssh_bind_free(sshbind);
    vTaskDelete(NULL);
    return;
  }

  Serial.printf("[ssh] listening on port %d\n", ssh_port);

  while (1) {
    ssh_session session = ssh_new();

    if (ssh_bind_accept(sshbind, session) != SSH_OK) {
      Serial.printf("[ssh] accept error: %s\n", ssh_get_error(sshbind));
      ssh_free(session);
      vTaskDelay(pdMS_TO_TICKS(1000));
      continue;
    }

    Serial.println("[ssh] client connected");

    if (ssh_handle_key_exchange(session) != SSH_OK) {
      Serial.printf("[ssh] key exchange error: %s\n", ssh_get_error(session));
      ssh_disconnect(session);
      ssh_free(session);
      continue;
    }

    // Register server callbacks (auth + channel open)
    struct ssh_server_callbacks_struct server_cb = {};
    server_cb.userdata = NULL;
    server_cb.auth_password_function = on_auth_password;
    server_cb.channel_open_request_session_function = on_channel_open;
    ssh_callbacks_init(&server_cb);
    ssh_set_server_callbacks(session, &server_cb);
    ssh_set_auth_methods(session, SSH_AUTH_METHOD_PASSWORD);

    // Event loop for auth + channel open
    ssh_event event = ssh_event_new();
    ssh_event_add_session(event, session);

    active_chan = NULL;
    shell_requested = false;
    session_alive = true;

    // Channel callbacks — registered once when channel opens
    struct ssh_channel_callbacks_struct channel_cb = {};
    channel_cb.userdata = NULL;
    channel_cb.channel_data_function = on_channel_data;
    channel_cb.channel_pty_request_function = on_pty_request;
    channel_cb.channel_shell_request_function = on_shell_request;
    channel_cb.channel_eof_function = on_channel_eof;
    channel_cb.channel_close_function = on_channel_close;
    ssh_callbacks_init(&channel_cb);
    bool channel_cb_registered = false;

    // Phase 1: Wait for auth + channel + shell request (tight poll)
    while (session_alive && (!active_chan || !shell_requested)) {
      ssh_event_dopoll(event, 0);
      if (ssh_get_status(session) & (SSH_CLOSED | SSH_CLOSED_ERROR)) {
        session_alive = false;
        break;
      }

      if (active_chan && !channel_cb_registered) {
        ssh_set_channel_callbacks(active_chan, &channel_cb);
        channel_cb_registered = true;
      }

      vTaskDelay(pdMS_TO_TICKS(1));
    }

    if (!session_alive || !active_chan || !shell_requested) {
      Serial.println("[ssh] session setup failed");
      ssh_event_remove_session(event, session);
      ssh_event_free(event);
      if (active_chan) { ssh_channel_free(active_chan); active_chan = NULL; }
      ssh_disconnect(session);
      ssh_free(session);
      continue;
    }

    // Phase 2: Shell session — MicroShell over SSH
    Serial.println("[ssh] shell session started");
    ssh_shell_setup();

    while (session_alive) {
      ssh_event_dopoll(event, 50);
      while (ush_service(&ssh_ush)) {}  // drain all pending output
      ssh_write_flush();

      if (ssh_get_status(session) & (SSH_CLOSED | SSH_CLOSED_ERROR))
        break;
    }

    Serial.println("[ssh] shell session ended");

    ssh_event_remove_session(event, session);
    ssh_event_free(event);
    if (active_chan) {
      ssh_channel_send_eof(active_chan);
      ssh_channel_close(active_chan);
      ssh_channel_free(active_chan);
      active_chan = NULL;
    }
    ssh_disconnect(session);
    ssh_free(session);

    Serial.println("[ssh] ready for next connection");
  }
}

//------------------------------------------
//  Public API
//------------------------------------------
void ssh_server_start(void) {
  xTaskCreatePinnedToCore(ssh_server_task, "ssh", SSH_TASK_STACK_SIZE,
                          NULL, 2, NULL, 1);
}

//------------------------------------------
//  Tests
//  describe("SSH Server (smoke)")
//------------------------------------------
#ifdef PIO_UNIT_TESTING

#include "../../testing/it.h"

/// it("user observes that libssh initializes without crashing")
static void ssh_server_test_libssh_initializes(void) {
  TEST_MESSAGE("user asks the device to initialize libssh");

  libssh_begin();

  ssh_session session = ssh_new();
  TEST_ASSERT_NOT_NULL_MESSAGE(session,
    "device: ssh_new() returned NULL after libssh_begin()");

  TEST_MESSAGE("libssh initialized and session allocated");
  ssh_free(session);
}

/// it("user observes that an ed25519 host key can be generated in memory")
static void ssh_server_test_generates_ed25519_key(void) {
  TEST_MESSAGE("user asks the device to generate an ed25519 keypair");

  ssh_key key = NULL;
  int rc = ssh_pki_generate(SSH_KEYTYPE_ED25519, 0, &key);

  TEST_ASSERT_EQUAL_INT_MESSAGE(SSH_OK, rc,
    "device: ssh_pki_generate(ED25519) returned error");
  TEST_ASSERT_NOT_NULL_MESSAGE(key,
    "device: generated key pointer is NULL");

  enum ssh_keytypes_e key_type = ssh_key_type(key);
  TEST_ASSERT_EQUAL_INT_MESSAGE(SSH_KEYTYPE_ED25519, key_type,
    "device: key type is not ED25519");

  const char *key_type_name = ssh_key_type_to_char(key_type);
  TEST_ASSERT_EQUAL_STRING_MESSAGE("ssh-ed25519", key_type_name,
    "device: key type string does not match expected");

  TEST_MESSAGE("ed25519 keypair generated successfully");
  ssh_key_free(key);
}

/// it("user observes that ssh_bind can be created and bound to a port")
static void ssh_server_test_bind_configures(void) {
  TEST_MESSAGE("user asks the device to create an SSH bind on port 2222");

  ssh_bind sshbind = ssh_bind_new();
  TEST_ASSERT_NOT_NULL_MESSAGE(sshbind,
    "device: ssh_bind_new() returned NULL");

  int test_port = 2222;
  int rc = ssh_bind_options_set(sshbind, SSH_BIND_OPTIONS_BINDPORT, &test_port);
  TEST_ASSERT_EQUAL_INT_MESSAGE(SSH_OK, rc,
    "device: failed to set SSH_BIND_OPTIONS_BINDPORT");

  rc = ssh_bind_options_set(sshbind, SSH_BIND_OPTIONS_BINDADDR, "0.0.0.0");
  TEST_ASSERT_EQUAL_INT_MESSAGE(SSH_OK, rc,
    "device: failed to set SSH_BIND_OPTIONS_BINDADDR");

  TEST_MESSAGE("ssh_bind created and configured");
  ssh_bind_free(sshbind);
}

/// it("user observes that the default configuration constants are sane")
static void ssh_server_test_config_defaults(void) {
  TEST_MESSAGE("user verifies SSH server configuration defaults");

  TEST_ASSERT_EQUAL_INT_MESSAGE(22, SSH_DEFAULT_PORT,
    "device: default SSH port should be 22");
  TEST_ASSERT_NOT_NULL_MESSAGE(SSH_DEFAULT_USER,
    "device: default SSH user must not be NULL");
  TEST_ASSERT_NOT_EMPTY_MESSAGE(SSH_DEFAULT_USER,
    "device: default SSH user must not be empty");
  TEST_ASSERT_GREATER_THAN_UINT32_MESSAGE(0, SSH_BUF_SIZE,
    "device: SSH buffer size must be > 0");
  TEST_ASSERT_GREATER_OR_EQUAL_UINT32_MESSAGE(10240, SSH_TASK_STACK_SIZE,
    "device: SSH task stack must be >= 10240 for libssh key exchange");

  TEST_ASSERT_NOT_NULL_MESSAGE(SSH_DEFAULT_HOSTKEY,
    "device: host key path must not be NULL");
  TEST_ASSERT_NOT_EMPTY_MESSAGE(SSH_DEFAULT_HOSTKEY,
    "device: host key path must not be empty");

  TEST_MESSAGE("configuration defaults are sane");
}

void ssh_server_run_tests(void) {
  it("user observes that libssh initializes without crashing",
     ssh_server_test_libssh_initializes);
  it("user observes that an ed25519 host key can be generated in memory",
     ssh_server_test_generates_ed25519_key);
  it("user observes that ssh_bind can be created and bound to a port",
     ssh_server_test_bind_configures);
  it("user observes that the default configuration constants are sane",
     ssh_server_test_config_defaults);
}

#endif
