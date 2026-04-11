#ifdef PIO_UNIT_TESTING

#include "smtp.h"
#include "../testing/it.h"

#include <Arduino.h>
#include <string.h>

static void test_endpoint_matches_flags(void) {
  char host[128] = {0};
  uint16_t port = 0;

#if CONFIG_SMTP_ENABLED
  bool ok = smtp_get_endpoint(host, sizeof(host), &port);
  TEST_ASSERT_TRUE_MESSAGE(ok, "smtp_get_endpoint returned false");
  TEST_ASSERT_EQUAL_STRING(CONFIG_SMTP_HOST, host);
  TEST_ASSERT_EQUAL_UINT16(CONFIG_SMTP_PORT, port);
#else
  bool ok = smtp_get_endpoint(host, sizeof(host), &port);
  TEST_ASSERT_FALSE_MESSAGE(ok, "should fail when SMTP not configured");
#endif
}

static void test_flags_are_valid(void) {
#if CONFIG_SMTP_ENABLED
  TEST_ASSERT_TRUE_MESSAGE(strlen(CONFIG_SMTP_HOST) > 0,
                           "CONFIG_SMTP_HOST must not be empty");
  TEST_ASSERT_TRUE_MESSAGE(CONFIG_SMTP_PORT > 0,
                           "CONFIG_SMTP_PORT must be > 0");
  TEST_ASSERT_TRUE_MESSAGE(strlen(CONFIG_SMTP_DOMAIN) > 0,
                           "CONFIG_SMTP_DOMAIN must not be empty");
  TEST_ASSERT_TRUE_MESSAGE(strlen(CONFIG_SMTP_FROM_EMAIL) > 0,
                           "CONFIG_SMTP_FROM_EMAIL must not be empty");
  TEST_ASSERT_TRUE_MESSAGE(strlen(CONFIG_SMTP_TO_EMAIL) > 0,
                           "CONFIG_SMTP_TO_EMAIL must not be empty");
#else
  TEST_IGNORE_MESSAGE("SMTP not enabled");
#endif
}

static void test_connects_with_flags(void) {
#if CONFIG_SMTP_ENABLED
  TEST_ASSERT_TRUE_MESSAGE(smtp_connect(), "smtp_connect failed");
#else
  TEST_IGNORE_MESSAGE("SMTP not enabled");
#endif
}

static void test_sends_test_email(void) {
#if CONFIG_SMTP_ENABLED && CONFIG_SMTP_TEST_ENABLED
  TEST_ASSERT_TRUE_MESSAGE(smtp_send_test_email(),
                           "smtp_send_test_email failed");
#else
  TEST_IGNORE_MESSAGE("SMTP test sending not enabled");
#endif
}

void smtp_run_tests(void) {
  it("smtp endpoint matches build flags", test_endpoint_matches_flags);
  it("smtp build flags are valid",        test_flags_are_valid);
  it("smtp connects with build flags",    test_connects_with_flags);
  it("smtp sends test email",             test_sends_test_email);
}

#endif
