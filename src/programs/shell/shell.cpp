#include "shell.h"
#include "commands.h"
#include "microfetch.h"
#include "fs/fs.h"
#include "../ssh/ssh_client.h"

#include <Arduino.h>
#include <WiFi.h>
#include <ESPmDNS.h>
#include <microshell.h>
#include <string.h>

//------------------------------------------
//  Shared hostname (mutable at runtime)
//------------------------------------------
static char hostname_data[CONFIG_SHELL_HOSTNAME_SIZE + 1] = CONFIG_HOSTNAME;

char *shell_get_hostname(void) {
  return hostname_data;
}

void shell_set_hostname(const char *hostname) {
  strncpy(hostname_data, hostname, CONFIG_SHELL_HOSTNAME_SIZE);
  hostname_data[CONFIG_SHELL_HOSTNAME_SIZE] = '\0';

  // Propagate to network layer
  WiFi.setHostname(hostname_data);
  MDNS.end();
  if (MDNS.begin(hostname_data)) {
    MDNS.addService("ssh", "tcp", CONFIG_SSH_PORT);
    MDNS.addService("http", "tcp", CONFIG_HTTP_PORT);
  }
}

//------------------------------------------
//  Serial I/O interface
//------------------------------------------
static int serial_read(struct ush_object *self, char *ch) {
  (void)self;
  if (Serial.available() > 0) {
    *ch = Serial.read();
    return 1;
  }
  return 0;
}

static int serial_write(struct ush_object *self, char ch) {
  (void)self;
  return (Serial.write(ch) == 1);
}

static const struct ush_io_interface serial_io = {
  .read = serial_read,
  .write = serial_write,
};

//------------------------------------------
//  Serial shell instance
//------------------------------------------
static char serial_in_buf[CONFIG_SHELL_BUF_IN];
static char serial_out_buf[CONFIG_SHELL_BUF_OUT];
static struct ush_object serial_ush;

static const struct ush_descriptor serial_desc = {
  .io = &serial_io,
  .input_buffer = serial_in_buf,
  .input_buffer_size = sizeof(serial_in_buf),
  .output_buffer = serial_out_buf,
  .output_buffer_size = sizeof(serial_out_buf),
  .path_max_length = CONFIG_SHELL_PATH_MAX,
  .hostname = hostname_data,
};

//------------------------------------------
//  Public API
//------------------------------------------
void shell_init_instance(struct ush_object *ush,
                         const struct ush_descriptor *desc) {
  // Tear down any previous state before reinitializing.
  // Without this, reused static ush_node_objects create cyclic linked lists
  // because ush_commands_add/ush_node_mount prepend via node->next, and the
  // stale next pointers from the previous init form a loop.
  // ush_deinit() zeros all mounted filesystem nodes recursively and then
  // memsets the ush_object, so ush_init() starts from a clean NULL state.
  // Safe on first call: zero-initialized root is NULL, recursion is a no-op.
  ush_deinit(ush);

  ush_init(ush, desc);
  commands_register(ush);
  microfetch_register(ush);
  ssh_client_commands_register(ush);
  fs_mount(ush);
}

void shell_init(void) {
  shell_init_instance(&serial_ush, &serial_desc);
}

void shell_service(void) {
  ush_service(&serial_ush);
}

//------------------------------------------
//  Tests
//  describe("Shell")
//------------------------------------------
#ifdef PIO_UNIT_TESTING

#include "../../testing/it.h"

static void shell_test_initializes(void) {
  TEST_MESSAGE("user asks the device to initialize microshell");

  shell_init();

  TEST_MESSAGE("microshell initialized with serial I/O");
}

static void shell_test_hostname_mutable(void) {
  TEST_MESSAGE("user sets hostname to 'ceratina'");

  shell_set_hostname("ceratina");
  TEST_ASSERT_EQUAL_STRING_MESSAGE("ceratina", shell_get_hostname(),
    "device: hostname should be 'ceratina' after set");

  shell_set_hostname(CONFIG_HOSTNAME);
  TEST_ASSERT_EQUAL_STRING_MESSAGE(CONFIG_HOSTNAME, shell_get_hostname(),
    "device: hostname should be restored to default");

  TEST_MESSAGE("hostname is mutable at runtime");
}

static void shell_test_custom_instance(void) {
  TEST_MESSAGE("user creates a second shell instance");

  static char in2[64], out2[64];
  static struct ush_object ush2;
  static const struct ush_io_interface null_io = {
    .read = [](struct ush_object *, char *) -> int { return 0; },
    .write = [](struct ush_object *, char) -> int { return 1; },
  };
  static const struct ush_descriptor desc2 = {
    .io = &null_io,
    .input_buffer = in2,
    .input_buffer_size = sizeof(in2),
    .output_buffer = out2,
    .output_buffer_size = sizeof(out2),
    .path_max_length = 64,
    .hostname = "test",
  };

  shell_init_instance(&ush2, &desc2);
  TEST_ASSERT_NOT_NULL_MESSAGE(ush2.root,
    "device: custom instance root node is NULL");

  TEST_MESSAGE("custom shell instance initialized with shared filesystem");
}

static void shell_test_reinit_no_cycle(void) {
  TEST_MESSAGE("user reinitializes the same shell instance twice");

  static char in3[64], out3[64];
  static struct ush_object ush3;
  static const struct ush_io_interface null_io = {
    .read = [](struct ush_object *, char *) -> int { return 0; },
    .write = [](struct ush_object *, char) -> int { return 1; },
  };
  static const struct ush_descriptor desc3 = {
    .io = &null_io,
    .input_buffer = in3,
    .input_buffer_size = sizeof(in3),
    .output_buffer = out3,
    .output_buffer_size = sizeof(out3),
    .path_max_length = 64,
    .hostname = "test",
  };

  // Initialize twice — this is what ssh_shell_setup() does on reconnect.
  // Without ush_deinit(), the second init creates a cyclic command list.
  shell_init_instance(&ush3, &desc3);
  shell_init_instance(&ush3, &desc3);

  // Walk the command list the same way help does (ush_cmd_help.c:40,83).
  // If the list is cyclic, this loop will exceed the bound.
  struct ush_node_object *node = ush3.commands;
  int count = 0;
  const int max_nodes = 64;
  while (node != NULL && count < max_nodes) {
    node = node->next;
    count++;
  }

  char message[64];
  snprintf(message, sizeof(message),
           "command list has %d node(s), terminated: %s",
           count, node == NULL ? "yes" : "NO — CYCLE DETECTED");
  TEST_MESSAGE(message);

  TEST_ASSERT_NULL_MESSAGE(node,
    "device: command list is cyclic after reinit — help would loop forever");

  // Also verify the filesystem tree root is intact
  TEST_ASSERT_NOT_NULL_MESSAGE(ush3.root,
    "device: root node is NULL after reinit");

  TEST_MESSAGE("reinit produces clean non-cyclic command list");
}

static void shell_test_hostname_default(void) {
  TEST_MESSAGE("user checks boot-time hostname without calling set first");
  TEST_ASSERT_EQUAL_STRING_MESSAGE(CONFIG_HOSTNAME, shell_get_hostname(),
    "device: boot-time hostname should match CONFIG_HOSTNAME");
  TEST_MESSAGE("default hostname verified");
}

static void shell_test_hostname_truncation(void) {
  TEST_MESSAGE("user sets a hostname longer than CONFIG_SHELL_HOSTNAME_SIZE");

  char long_name[CONFIG_SHELL_HOSTNAME_SIZE + 20];
  memset(long_name, 'A', sizeof(long_name) - 1);
  long_name[sizeof(long_name) - 1] = '\0';

  shell_set_hostname(long_name);

  size_t result_len = strlen(shell_get_hostname());
  TEST_ASSERT_LESS_OR_EQUAL_UINT32_MESSAGE(CONFIG_SHELL_HOSTNAME_SIZE, result_len,
    "device: hostname exceeds CONFIG_SHELL_HOSTNAME_SIZE after truncation");

  shell_set_hostname(CONFIG_HOSTNAME);
  TEST_MESSAGE("hostname truncation verified");
}

void shell_run_tests(void) {
  it("user observes that microshell initializes",
     shell_test_initializes);
  it("user observes that the hostname is mutable",
     shell_test_hostname_mutable);
  it("user observes that a custom shell instance can be initialized",
     shell_test_custom_instance);
  it("user observes that reinitializing a shell instance does not create cycles",
     shell_test_reinit_no_cycle);
  it("user observes that the default hostname matches CONFIG_HOSTNAME",
     shell_test_hostname_default);
  it("user observes that long hostnames are truncated",
     shell_test_hostname_truncation);
}

#endif
