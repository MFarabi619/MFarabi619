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
}

//------------------------------------------
//  Tests
//------------------------------------------
#ifdef PIO_UNIT_TESTING

#include <testing/utils.h>

static void coreutils_test_date_succeeds(void) {
  TEST_MESSAGE("user runs date with no arguments");
  char *argv[] = {(char *)"date"};
  TEST_ASSERT_EQUAL_INT(0, programs::coreutils::cmd_date(1, argv));
}

static void coreutils_test_date_rejects_extra_args(void) {
  TEST_MESSAGE("user runs date with extra arguments");
  char *argv[] = {(char *)"date", (char *)"extra"};
  TEST_ASSERT_EQUAL_INT(1, programs::coreutils::cmd_date(2, argv));
}

static void coreutils_test_uptime_succeeds(void) {
  TEST_MESSAGE("user runs uptime");
  char *argv[] = {(char *)"uptime"};
  TEST_ASSERT_EQUAL_INT(0, programs::coreutils::cmd_uptime(1, argv));
}

static void coreutils_test_free_succeeds(void) {
  TEST_MESSAGE("user runs free");
  char *argv[] = {(char *)"free"};
  TEST_ASSERT_EQUAL_INT(0, programs::coreutils::cmd_free(1, argv));
}

static void coreutils_test_hostname_reads(void) {
  TEST_MESSAGE("user reads hostname");
  char *argv[] = {(char *)"hostname"};
  TEST_ASSERT_EQUAL_INT(0, programs::coreutils::cmd_hostname(1, argv));
}

static void coreutils_test_hostname_rejects_three_args(void) {
  TEST_MESSAGE("user runs hostname with too many arguments");
  char *argv[] = {(char *)"hostname", (char *)"a", (char *)"b"};
  TEST_ASSERT_EQUAL_INT(1, programs::coreutils::cmd_hostname(3, argv));
}

static void coreutils_test_ip_succeeds(void) {
  TEST_MESSAGE("user runs ip");
  char *argv[] = {(char *)"ip"};
  TEST_ASSERT_EQUAL_INT(0, programs::coreutils::cmd_ifconfig(1, argv));
}

static void coreutils_test_echo_succeeds(void) {
  TEST_MESSAGE("user runs echo with text");
  char *argv[] = {(char *)"echo", (char *)"hello"};
  TEST_ASSERT_EQUAL_INT(0, programs::coreutils::cmd_print(2, argv));
}

static void coreutils_test_echo_rejects_no_args(void) {
  TEST_MESSAGE("user runs echo without arguments");
  char *argv[] = {(char *)"echo"};
  TEST_ASSERT_EQUAL_INT(1, programs::coreutils::cmd_print(1, argv));
}

static void coreutils_test_sensors_succeeds(void) {
  TEST_MESSAGE("user runs sensors");
  char *argv[] = {(char *)"sensors"};
  TEST_ASSERT_EQUAL_INT(0, programs::coreutils::cmd_sensors(1, argv));
}

static void coreutils_test_whoami_succeeds(void) {
  TEST_MESSAGE("user runs whoami");
  char *argv[] = {(char *)"whoami"};
  TEST_ASSERT_EQUAL_INT(0, programs::coreutils::cmd_whoami(1, argv));
}

void programs::coreutils::test() {
  it("user runs date successfully", coreutils_test_date_succeeds);
  it("user observes date rejects extra arguments", coreutils_test_date_rejects_extra_args);
  it("user runs uptime successfully", coreutils_test_uptime_succeeds);
  it("user runs free successfully", coreutils_test_free_succeeds);
  it("user reads hostname successfully", coreutils_test_hostname_reads);
  it("user observes hostname rejects too many arguments", coreutils_test_hostname_rejects_three_args);
  it("user runs ip successfully", coreutils_test_ip_succeeds);
  it("user runs echo with text successfully", coreutils_test_echo_succeeds);
  it("user observes echo rejects missing argument", coreutils_test_echo_rejects_no_args);
  it("user runs sensors successfully", coreutils_test_sensors_succeeds);
  it("user runs whoami successfully", coreutils_test_whoami_succeeds);
}

#endif
