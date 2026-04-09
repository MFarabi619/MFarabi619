#include "shell.h"
#include "commands.h"
#include "fs/fs.h"

#include <Arduino.h>
#include <microshell.h>
#include <string.h>

//------------------------------------------
//  Shared hostname (mutable at runtime)
//------------------------------------------
static char hostname_data[SHELL_HOSTNAME_SIZE + 1] = SHELL_HOSTNAME;

char *shell_get_hostname(void) {
  return hostname_data;
}

void shell_set_hostname(const char *hostname) {
  strncpy(hostname_data, hostname, SHELL_HOSTNAME_SIZE);
  hostname_data[SHELL_HOSTNAME_SIZE] = '\0';
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
static char serial_in_buf[SHELL_BUF_IN_SIZE];
static char serial_out_buf[SHELL_BUF_OUT_SIZE];
static struct ush_object serial_ush;

static const struct ush_descriptor serial_desc = {
  .io = &serial_io,
  .input_buffer = serial_in_buf,
  .input_buffer_size = sizeof(serial_in_buf),
  .output_buffer = serial_out_buf,
  .output_buffer_size = sizeof(serial_out_buf),
  .path_max_length = SHELL_PATH_MAX_SIZE,
  .hostname = hostname_data,
};

//------------------------------------------
//  Public API
//------------------------------------------
void shell_init_instance(struct ush_object *ush,
                         const struct ush_descriptor *desc) {
  ush_init(ush, desc);
  commands_register(ush);
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

#include <unity.h>

static char _it_buf[256];
static void _it_run(void (*func)(void), const char *desc, int line) {
  strncpy(_it_buf, desc, sizeof(_it_buf) - 1);
  _it_buf[sizeof(_it_buf) - 1] = '\0';
  for (char *p = _it_buf; *p; p++) {
    if (*p == ' ') *p = '_';
  }
  UnityDefaultTestRun(func, _it_buf, line);
}
#define it(description, test_func) \
  _it_run(test_func, description, __LINE__)

/// it("user observes that microshell initializes")
static void shell_test_initializes(void) {
  TEST_MESSAGE("user asks the device to initialize microshell");

  shell_init();

  TEST_MESSAGE("microshell initialized with serial I/O");
}

/// it("user observes that the hostname is mutable")
static void shell_test_hostname_mutable(void) {
  TEST_MESSAGE("user sets hostname to 'ceratina'");

  shell_set_hostname("ceratina");
  TEST_ASSERT_EQUAL_STRING_MESSAGE("ceratina", shell_get_hostname(),
    "device: hostname should be 'ceratina' after set");

  shell_set_hostname(SHELL_HOSTNAME);
  TEST_ASSERT_EQUAL_STRING_MESSAGE(SHELL_HOSTNAME, shell_get_hostname(),
    "device: hostname should be restored to default");

  TEST_MESSAGE("hostname is mutable at runtime");
}

/// it("user observes that a custom shell instance can be initialized")
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

void shell_run_tests(void) {
  it("user observes that microshell initializes",
     shell_test_initializes);
  it("user observes that the hostname is mutable",
     shell_test_hostname_mutable);
  it("user observes that a custom shell instance can be initialized",
     shell_test_custom_instance);
}

#endif
