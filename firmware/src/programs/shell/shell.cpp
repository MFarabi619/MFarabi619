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
static char hostname_data[config::shell::HOSTNAME_SIZE + 1] = {};

static bool hostname_initialized = false;
static void ensure_hostname(void) {
  if (!hostname_initialized) {
    strncpy(hostname_data, config::HOSTNAME, config::shell::HOSTNAME_SIZE);
    hostname_initialized = true;
  }
}

char *programs::shell::accessHostname(void) {
  ensure_hostname();
  return hostname_data;
}

void programs::shell::configureHostname(const char *hostname) {
  strncpy(hostname_data, hostname, config::shell::HOSTNAME_SIZE);
  hostname_data[config::shell::HOSTNAME_SIZE] = '\0';

  // Propagate to network layer
  WiFi.setHostname(hostname_data);
  MDNS.end();
  if (MDNS.begin(hostname_data)) {
    MDNS.addService("ssh", "tcp", config::ssh::PORT);
    MDNS.addService("http", "tcp", config::http::PORT);
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
static char serial_in_buf[config::shell::BUF_IN];
static char serial_out_buf[config::shell::BUF_OUT];
static struct ush_object serial_ush;

static const struct ush_descriptor serial_desc = {
  .io = &serial_io,
  .input_buffer = serial_in_buf,
  .input_buffer_size = sizeof(serial_in_buf),
  .output_buffer = serial_out_buf,
  .output_buffer_size = sizeof(serial_out_buf),
  .path_max_length = config::shell::MAX_PATH_LEN,
  .hostname = hostname_data,
};

//------------------------------------------
//  Public API
//------------------------------------------
void programs::shell::initInstance(struct ush_object *ush,
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
  programs::shell::commands::registerAll(ush);
  programs::shell::microfetch::registerNode(ush);
  programs::ssh_client::registerCommands(ush);
  programs::shell::fs::mount(ush);
}

void programs::shell::initialize() {
  programs::shell::initInstance(&serial_ush, &serial_desc);
}

void programs::shell::service() {
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

  programs::shell::initialize();

  TEST_MESSAGE("microshell initialized with serial I/O");
}

static void shell_test_hostname_mutable(void) {
  TEST_MESSAGE("user sets hostname to 'ceratina'");

  programs::shell::configureHostname("ceratina");
  TEST_ASSERT_EQUAL_STRING_MESSAGE("ceratina", programs::shell::accessHostname(),
    "device: hostname should be 'ceratina' after set");

  programs::shell::configureHostname(config::HOSTNAME);
  TEST_ASSERT_EQUAL_STRING_MESSAGE(config::HOSTNAME, programs::shell::accessHostname(),
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

  programs::shell::initInstance(&ush2, &desc2);
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
  programs::shell::initInstance(&ush3, &desc3);
  programs::shell::initInstance(&ush3, &desc3);

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
  TEST_ASSERT_EQUAL_STRING_MESSAGE(config::HOSTNAME, programs::shell::accessHostname(),
    "device: boot-time hostname should match config::HOSTNAME");
  TEST_MESSAGE("default hostname verified");
}

static void shell_test_hostname_truncation(void) {
  TEST_MESSAGE("user sets a hostname longer than config::shell::HOSTNAME_SIZE");

  char long_name[config::shell::HOSTNAME_SIZE + 20];
  memset(long_name, 'A', sizeof(long_name) - 1);
  long_name[sizeof(long_name) - 1] = '\0';

  programs::shell::configureHostname(long_name);

  size_t result_len = strlen(programs::shell::accessHostname());
  TEST_ASSERT_LESS_OR_EQUAL_UINT32_MESSAGE(config::shell::HOSTNAME_SIZE, result_len,
    "device: hostname exceeds config::shell::HOSTNAME_SIZE after truncation");

  programs::shell::configureHostname(config::HOSTNAME);
  TEST_MESSAGE("hostname truncation verified");
}

void programs::shell::test(void) {
  it("user observes that microshell initializes",
     shell_test_initializes);
  it("user observes that the hostname is mutable",
     shell_test_hostname_mutable);
  it("user observes that a custom shell instance can be initialized",
     shell_test_custom_instance);
  it("user observes that reinitializing a shell instance does not create cycles",
     shell_test_reinit_no_cycle);
  it("user observes that the default hostname matches config::HOSTNAME",
     shell_test_hostname_default);
  it("user observes that long hostnames are truncated",
     shell_test_hostname_truncation);
}

#endif
