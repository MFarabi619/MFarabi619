#ifdef PIO_UNIT_TESTING

#include "http.h"
#include "../testing/it.h"

static void http_test_port_default(void) {
  TEST_MESSAGE("user verifies HTTP server configuration");

  TEST_ASSERT_EQUAL_INT_MESSAGE(80, CONFIG_HTTP_PORT,
    "device: HTTP port should be 80");

  TEST_MESSAGE("HTTP port is 80");
}

void http_run_tests(void) {
  it("user observes that HTTP port is configured to 80",
     http_test_port_default);
}

#endif
