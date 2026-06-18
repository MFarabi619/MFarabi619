#include <check.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

/* Import actual production code */
#include "libs/firmware/networking/dns/proxy.c"

START_TEST(test_dns_proxy_rejects_unauthenticated)
{
    /* Invariant: DNS proxy must reject unauthenticated/malformed requests
     * without performing unsafe buffer operations (CWE-287 / buffer overflow) */

    struct {
        const uint8_t *data;
        size_t len;
        const char *desc;
    } payloads[] = {
        /* Exact exploit: oversized qname to overflow fixed buffer */
        { (const uint8_t *)"\x01" "\xff\xff\xff\xff\xff\xff\xff\xff"
                           "\xff\xff\xff\xff\xff\xff\xff\xff"
                           "\xff\xff\xff\xff\xff\xff\xff\xff"
                           "\xff\xff\xff\xff\xff\xff\xff\xff"
                           "\xff\xff\xff\xff\xff\xff\xff\xff"
                           "\xff\xff\xff\xff\xff\xff\xff\xff"
                           "\xff\xff\xff\xff\xff\xff\xff\xff"
                           "\xff\xff\xff\xff\xff\xff\xff\xff", 65, "oversized_qname_exploit" },
        /* Boundary: exactly max buffer size (no auth token present) */
        { (const uint8_t *)"\x00\x00\x00\x00\x00\x00\x00\x00"
                           "\x00\x00\x00\x00\x00\x00\x00\x00", 16, "boundary_no_auth" },
        /* Valid-looking DNS query but missing authentication */
        { (const uint8_t *)"\x03www\x06google\x03com\x00", 18, "valid_query_no_auth" },
    };
    int num_payloads = sizeof(payloads) / sizeof(payloads[0]);

    for (int i = 0; i < num_payloads; i++) {
        int result = dns_proxy_handle_request(payloads[i].data, payloads[i].len,
                                              NULL /* no auth token */);
        /* Must return an error/rejection code, never success (0) on unauthenticated input */
        ck_assert_msg(result != 0,
            "Payload '%s': unauthenticated request must be rejected (got result=0)",
            payloads[i].desc);
        /* Must not return HTTP-like 200 or DNS success without auth */
        ck_assert_msg(result == 401 || result == 403 || result < 0,
            "Payload '%s': expected 401/403/negative, got %d",
            payloads[i].desc, result);
    }
}
END_TEST

Suite *security_suite(void)
{
    Suite *s;
    TCase *tc_core;

    s = suite_create("Security");
    tc_core = tcase_create("Core");

    tcase_add_test(tc_core, test_dns_proxy_rejects_unauthenticated);
    suite_add_tcase(s, tc_core);

    return s;
}

int main(void)
{
    int number_failed;
    Suite *s;
    SRunner *sr;

    s = security_suite();
    sr = srunner_create(s);

    srunner_run_all(sr, CK_NORMAL);
    number_failed = srunner_ntests_failed(sr);
    srunner_free(sr);

    return (number_failed == 0) ? EXIT_SUCCESS : EXIT_FAILURE;
}