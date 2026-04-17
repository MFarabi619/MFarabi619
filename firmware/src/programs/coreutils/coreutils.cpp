#include "coreutils.h"

#include <Console.h>

void programs::coreutils::registerAll() {
  Console.addCmd("date",     "show local date and time",       cmd_date);
  Console.addCmd("uptime",   "show system uptime",             cmd_uptime);
  Console.addCmd("free",     "show memory usage",              cmd_free);
  Console.addCmd("hostname", "read or set hostname",           "<new-name>", cmd_hostname);
  Console.addCmd("ip",       "show network interface status",  cmd_ifconfig);
  Console.addCmd("echo",     "print argument to shell",        "<text>", cmd_print);
  Console.addCmd("sensors",  "show sensor inventory summary",  cmd_sensors);
  Console.addCmd("whoami",   "print current user",             cmd_whoami);
  Console.addCmd("ls",       "list directory contents",         "[path]", cmd_ls);
  Console.addCmd("cat",      "print file contents",             "<file>", cmd_cat);
  Console.addCmd("mkdir",    "create directory",                "<name>", cmd_mkdir);
  Console.addCmd("rm",       "remove file",                     "<name>", cmd_rm);
  Console.addCmd("touch",    "create empty file",               "<name>", cmd_touch);
  Console.addCmd("cp",       "copy file",                       "<src> <dst>", cmd_cp);
  Console.addCmd("mv",       "move or rename file",             "<src> <dst>", cmd_mv);
  Console.addCmd("df",       "show disk usage",                 cmd_df);
  Console.addCmd("i2cdetect", "scan I2C bus for devices",       "[-l] [-m <ch>] [bus]", cmd_i2cdetect);
}

//------------------------------------------
//  Tests
//------------------------------------------
#ifdef PIO_UNIT_TESTING

#include <testing/utils.h>

static void test_coreutils_date(void) {
  WHEN("date is run with no arguments");
  char *argv[] = {(char *)"date"};
  TEST_ASSERT_EQUAL_INT_MESSAGE(0, programs::coreutils::cmd_date(1, argv),
    "device: date should succeed with no arguments");
}

static void test_coreutils_date_rejects_extra_args(void) {
  WHEN("date is run with extra arguments");
  char *argv[] = {(char *)"date", (char *)"extra"};
  TEST_ASSERT_EQUAL_INT_MESSAGE(1, programs::coreutils::cmd_date(2, argv),
    "device: date should reject extra arguments");
}

static void test_coreutils_uptime(void) {
  WHEN("uptime is run");
  char *argv[] = {(char *)"uptime"};
  TEST_ASSERT_EQUAL_INT_MESSAGE(0, programs::coreutils::cmd_uptime(1, argv),
    "device: uptime should succeed");
}

static void test_coreutils_free(void) {
  WHEN("free is run");
  char *argv[] = {(char *)"free"};
  TEST_ASSERT_EQUAL_INT_MESSAGE(0, programs::coreutils::cmd_free(1, argv),
    "device: free should succeed");
}

static void test_coreutils_hostname(void) {
  WHEN("hostname is run");
  char *argv[] = {(char *)"hostname"};
  TEST_ASSERT_EQUAL_INT_MESSAGE(0, programs::coreutils::cmd_hostname(1, argv),
    "device: hostname should succeed with no arguments");
}

static void test_coreutils_hostname_rejects_extra_args(void) {
  WHEN("hostname is run with too many arguments");
  char *argv[] = {(char *)"hostname", (char *)"a", (char *)"b"};
  TEST_ASSERT_EQUAL_INT_MESSAGE(1, programs::coreutils::cmd_hostname(3, argv),
    "device: hostname should reject more than one argument");
}

static void test_coreutils_ip(void) {
  WHEN("ip is run");
  char *argv[] = {(char *)"ip"};
  TEST_ASSERT_EQUAL_INT_MESSAGE(0, programs::coreutils::cmd_ifconfig(1, argv),
    "device: ip should succeed");
}

static void test_coreutils_echo(void) {
  WHEN("echo is run with text");
  char *argv[] = {(char *)"echo", (char *)"hello"};
  TEST_ASSERT_EQUAL_INT_MESSAGE(0, programs::coreutils::cmd_print(2, argv),
    "device: echo should succeed with text argument");
}

static void test_coreutils_echo_rejects_no_args(void) {
  WHEN("echo is run without arguments");
  char *argv[] = {(char *)"echo"};
  TEST_ASSERT_EQUAL_INT_MESSAGE(1, programs::coreutils::cmd_print(1, argv),
    "device: echo should reject missing argument");
}

static void test_coreutils_sensors(void) {
  WHEN("sensors is run");
  char *argv[] = {(char *)"sensors"};
  TEST_ASSERT_EQUAL_INT_MESSAGE(0, programs::coreutils::cmd_sensors(1, argv),
    "device: sensors should succeed");
}

static void test_coreutils_whoami(void) {
  WHEN("whoami is run");
  char *argv[] = {(char *)"whoami"};
  TEST_ASSERT_EQUAL_INT_MESSAGE(0, programs::coreutils::cmd_whoami(1, argv),
    "device: whoami should succeed");
}

void programs::coreutils::test() {
  MODULE("Coreutils");
  RUN_TEST(test_coreutils_date);
  RUN_TEST(test_coreutils_date_rejects_extra_args);
  RUN_TEST(test_coreutils_uptime);
  RUN_TEST(test_coreutils_free);
  RUN_TEST(test_coreutils_hostname);
  RUN_TEST(test_coreutils_hostname_rejects_extra_args);
  RUN_TEST(test_coreutils_ip);
  RUN_TEST(test_coreutils_echo);
  RUN_TEST(test_coreutils_echo_rejects_no_args);
  RUN_TEST(test_coreutils_sensors);
  RUN_TEST(test_coreutils_whoami);
}

#endif
