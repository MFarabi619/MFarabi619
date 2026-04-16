#include "ssh_server.h"
#include "console/prompt.h"
#include "console/remote.h"
#include <led.h>

#include <Arduino.h>
#include <LittleFS.h>

#include "libssh_esp32.h"
#include <libssh/callbacks.h>
#include <libssh/libssh.h>
#include <libssh/server.h>

#include <atomic>
#include <freertos/event_groups.h>
#include <sys/reent.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include <string.h>

static struct _reent reent_data_esp32;

static const char *ssh_user     = CONFIG_SSH_USER;
static const char *ssh_password = CONFIG_SSH_USER;
static const char *ssh_hostkey  = config::ssh::HOSTKEY_PATH;
static const int   ssh_port    = config::ssh::PORT;

static String ssh_hostkey_vfs(void) {
  return String(LittleFS.mountpoint()) + config::ssh::HOSTKEY_PATH;
}

static ssh_channel active_chan = nullptr;
static std::atomic<bool> shell_requested = false;
static std::atomic<bool> session_alive = true;

static EventGroupHandle_t ssh_events = nullptr;
constexpr EventBits_t SSH_BIT_CHANNEL_OPEN  = (1 << 0);
constexpr EventBits_t SSH_BIT_SHELL_REQUEST = (1 << 1);
constexpr EventBits_t SSH_BIT_SESSION_DEAD  = (1 << 2);

//------------------------------------------
//  Remote shell instance
//------------------------------------------
static char ssh_ring[config::ssh::RING_SIZE];
static char ssh_wbuf[config::ssh::WRITE_BUF_SIZE];
static char ssh_line[config::shell::BUF_IN];

static void ssh_flush(const char *data, size_t len, void *ctx) {
  (void)ctx;
  if (active_chan)
    ssh_channel_write(active_chan, data, len);
}

static console::remote::Shell shell(
  ssh_ring, config::ssh::RING_SIZE,
  ssh_wbuf, config::ssh::WRITE_BUF_SIZE,
  ssh_line, config::shell::BUF_IN,
  ssh_flush, nullptr
);

//------------------------------------------
//  LibSSH Callbacks
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
  Serial.println(F("[ssh] channel opened"));
  if (ssh_events) xEventGroupSetBits(ssh_events, SSH_BIT_CHANNEL_OPEN);
  return active_chan;
}

static int on_channel_data(ssh_session session, ssh_channel channel,
                           void *data, uint32_t len, int is_stderr,
                           void *userdata) {
  (void)session; (void)channel; (void)is_stderr; (void)userdata;
  char *bytes = (char *)data;
  for (uint32_t i = 0; i < len; i++) {
    if (bytes[i] == '\x04') {
      session_alive.store(false, std::memory_order_release);
      if (ssh_events) xEventGroupSetBits(ssh_events, SSH_BIT_SESSION_DEAD);
      return len;
    }
  }
  shell.push_input(bytes, len);
  return len;
}

static int on_pty_request(ssh_session session, ssh_channel channel,
                          const char *term, int width, int height,
                          int pxwidth, int pxheight, void *userdata) {
  (void)session; (void)channel; (void)term;
  (void)pxwidth; (void)pxheight; (void)userdata;
  Serial.printf("[ssh] pty request: %dx%d\n", width, height);
  if (width > 0)
    console::prompt::set_terminal_width((uint16_t)width);
  return 0;
}

static int on_shell_request(ssh_session session, ssh_channel channel,
                            void *userdata) {
  (void)session; (void)channel; (void)userdata;
  Serial.println(F("[ssh] shell requested"));
  shell_requested.store(true, std::memory_order_release);
  if (ssh_events) xEventGroupSetBits(ssh_events, SSH_BIT_SHELL_REQUEST);
  return 0;
}

static void on_channel_eof(ssh_session session, ssh_channel channel,
                           void *userdata) {
  (void)session; (void)channel; (void)userdata;
  session_alive.store(false, std::memory_order_release);
  if (ssh_events) xEventGroupSetBits(ssh_events, SSH_BIT_SESSION_DEAD);
}

static void on_channel_close(ssh_session session, ssh_channel channel,
                             void *userdata) {
  (void)session; (void)channel; (void)userdata;
  session_alive.store(false, std::memory_order_release);
  if (ssh_events) xEventGroupSetBits(ssh_events, SSH_BIT_SESSION_DEAD);
}

//------------------------------------------
//  Host Key
//------------------------------------------
static bool ssh_ensure_hostkey(void) {
  if (LittleFS.exists(ssh_hostkey)) {
    Serial.println(F("[ssh] host key found"));
    return true;
  }

  Serial.println(F("[ssh] generating ed25519 host key..."));
  LittleFS.mkdir("/.ssh");
  ssh_key key = nullptr;
  int rc = ssh_pki_generate(SSH_KEYTYPE_ED25519, 0, &key);
  if (rc != SSH_OK || key == nullptr) {
    Serial.println(F("[ssh] key generation failed"));
    return false;
  }

  String tmp_path = ssh_hostkey_vfs() + ".tmp";
  rc = ssh_pki_export_privkey_file(key, NULL, NULL, NULL, tmp_path.c_str());
  ssh_key_free(key);

  if (rc != SSH_OK) {
    Serial.printf("[ssh] failed to write key to %s\n", tmp_path.c_str());
    LittleFS.remove("/.ssh/id_ed25519.tmp");
    return false;
  }

  LittleFS.rename("/.ssh/id_ed25519.tmp", ssh_hostkey);
  Serial.printf("[ssh] host key saved to %s\n", ssh_hostkey_vfs().c_str());
  return true;
}

//------------------------------------------
//  Exit
//------------------------------------------
bool services::sshd::requestExit(void) {
  session_alive.store(false, std::memory_order_release);
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
    Serial.println(F("[ssh] cannot start without host key"));
    vTaskDelete(nullptr);
    return;
  }

  ssh_bind sshbind = ssh_bind_new();
  ssh_bind_options_set(sshbind, SSH_BIND_OPTIONS_BINDADDR, "0.0.0.0");
  ssh_bind_options_set(sshbind, SSH_BIND_OPTIONS_BINDPORT, &ssh_port);
  ssh_bind_options_set(sshbind, SSH_BIND_OPTIONS_HOSTKEY, ssh_hostkey_vfs().c_str());

  if (ssh_bind_listen(sshbind) < 0) {
    Serial.printf("[ssh] bind error: %s\n", ssh_get_error(sshbind));
    ssh_bind_free(sshbind);
    vTaskDelete(nullptr);
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

    Serial.println(F("[ssh] client connected"));
    LED.set(colors::White);

    if (ssh_handle_key_exchange(session) != SSH_OK) {
      Serial.printf("[ssh] key exchange error: %s\n", ssh_get_error(session));
      ssh_disconnect(session);
      ssh_free(session);
      continue;
    }

    struct ssh_server_callbacks_struct server_cb = {};
    server_cb.userdata = nullptr;
    server_cb.auth_password_function = on_auth_password;
    server_cb.channel_open_request_session_function = on_channel_open;
    ssh_callbacks_init(&server_cb);
    ssh_set_server_callbacks(session, &server_cb);
    ssh_set_auth_methods(session, SSH_AUTH_METHOD_PASSWORD);

    ssh_event event = ssh_event_new();
    ssh_event_add_session(event, session);

    active_chan = nullptr;
    shell_requested.store(false, std::memory_order_relaxed);
    session_alive.store(true, std::memory_order_relaxed);

    if (!ssh_events) ssh_events = xEventGroupCreate();
    xEventGroupClearBits(ssh_events, 0xFF);

    struct ssh_channel_callbacks_struct channel_cb = {};
    channel_cb.userdata = nullptr;
    channel_cb.channel_data_function = on_channel_data;
    channel_cb.channel_pty_request_function = on_pty_request;
    channel_cb.channel_shell_request_function = on_shell_request;
    channel_cb.channel_eof_function = on_channel_eof;
    channel_cb.channel_close_function = on_channel_close;
    ssh_callbacks_init(&channel_cb);
    bool is_channel_cb_registered = false;

    constexpr EventBits_t SSH_WAKE = SSH_BIT_CHANNEL_OPEN | SSH_BIT_SHELL_REQUEST | SSH_BIT_SESSION_DEAD;

    while (session_alive.load(std::memory_order_acquire) &&
           (!active_chan || !shell_requested.load(std::memory_order_acquire))) {
      ssh_event_dopoll(event, 0);
      if (ssh_get_status(session) & (SSH_CLOSED | SSH_CLOSED_ERROR)) {
        session_alive.store(false, std::memory_order_release);
        break;
      }

      if (active_chan && !is_channel_cb_registered) {
        ssh_set_channel_callbacks(active_chan, &channel_cb);
        is_channel_cb_registered = true;
      }

      xEventGroupWaitBits(ssh_events, SSH_WAKE, pdFALSE, pdFALSE, pdMS_TO_TICKS(50));
    }

    if (!session_alive.load(std::memory_order_acquire) ||
        !active_chan ||
        !shell_requested.load(std::memory_order_acquire)) {
      Serial.println(F("[ssh] session setup failed"));
      ssh_event_remove_session(event, session);
      ssh_event_free(event);
      if (active_chan) { ssh_channel_free(active_chan); active_chan = nullptr; }
      ssh_disconnect(session);
      ssh_free(session);
      continue;
    }

    Serial.println(F("[ssh] shell session started"));
    shell.reset();

    // Capture remote IP from SSH socket
    char remote_ip[32] = "";
    socket_t fd = ssh_get_fd(session);
    if (fd >= 0) {
      struct sockaddr_in addr;
      socklen_t addr_len = sizeof(addr);
      if (getpeername(fd, (struct sockaddr *)&addr, &addr_len) == 0)
        inet_ntoa_r(addr.sin_addr, remote_ip, sizeof(remote_ip));
    }

    shell.send_motd("SSH", remote_ip[0] ? remote_ip : nullptr);
    shell.send_prompt();

    while (session_alive.load(std::memory_order_acquire)) {
      ssh_event_dopoll(event, 100);
      shell.service();

      if (ssh_get_status(session) & (SSH_CLOSED | SSH_CLOSED_ERROR))
        break;
    }

    shell.save_history();
    Serial.println(F("[ssh] shell session ended"));

    ssh_event_remove_session(event, session);
    ssh_event_free(event);
    if (active_chan) {
      ssh_channel_send_eof(active_chan);
      ssh_channel_close(active_chan);
      ssh_channel_free(active_chan);
      active_chan = nullptr;
    }
    ssh_disconnect(session);
    ssh_free(session);

    Serial.println(F("[ssh] ready for next connection"));
    LED.set(colors::Green);
  }
}

bool services::sshd::initialize() {
  if (LittleFS.totalBytes() == 0) {
    Serial.println(F("[ssh] LittleFS not mounted — cannot start"));
    return false;
  }
  xTaskCreatePinnedToCore(ssh_server_task, "ssh", config::ssh::TASK_STACK,
                          NULL, 2, NULL, 1);
  return true;
}

#ifdef PIO_UNIT_TESTING

#include <testing/utils.h>

static void test_sshd_libssh_initializes(void) {
  WHEN("libssh is initialized");
  libssh_begin();
  ssh_session session = ssh_new();
  TEST_ASSERT_NOT_NULL_MESSAGE(session,
    "device: ssh_new() returned NULL after libssh_begin()");
  ssh_free(session);
}

static void test_sshd_generates_ed25519_key(void) {
  WHEN("an ed25519 keypair is generated");
  ssh_key key = nullptr;
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
  ssh_key_free(key);
}

static void test_sshd_bind_configures(void) {
  WHEN("an ssh_bind is created on port 2222");
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
  ssh_bind_free(sshbind);
}

static void test_sshd_config_defaults(void) {
  GIVEN("SSH server configuration constants");
  THEN("all defaults are sane");
  TEST_ASSERT_EQUAL_INT_MESSAGE(22, config::ssh::PORT,
    "device: default SSH port should be 22");
  TEST_ASSERT_NOT_NULL_MESSAGE(CONFIG_SSH_USER,
    "device: default SSH user must not be NULL");
  TEST_ASSERT_NOT_EMPTY_MESSAGE(CONFIG_SSH_USER,
    "device: default SSH user must not be empty");
  TEST_ASSERT_GREATER_OR_EQUAL_UINT32_MESSAGE(10240, config::ssh::TASK_STACK,
    "device: SSH task stack must be >= 10240 for libssh key exchange");
  TEST_ASSERT_NOT_NULL_MESSAGE(config::ssh::HOSTKEY_PATH,
    "device: host key path must not be NULL");
  TEST_ASSERT_NOT_EMPTY_MESSAGE(config::ssh::HOSTKEY_PATH,
    "device: host key path must not be empty");
}

void services::sshd::test() {
  RUN_TEST(test_sshd_libssh_initializes);
  RUN_TEST(test_sshd_generates_ed25519_key);
  RUN_TEST(test_sshd_bind_configures);
  RUN_TEST(test_sshd_config_defaults);
}

#endif
