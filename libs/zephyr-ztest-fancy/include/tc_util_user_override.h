#ifndef FIRMWARE_TESTS_TC_UTIL_USER_OVERRIDE_H
#define FIRMWARE_TESTS_TC_UTIL_USER_OVERRIDE_H

#define TC_PASS_STR "\x1b[1;30;102m[PASSED]\x1b[0m"
#define TC_FAIL_STR "\x1b[1;97;101m[FAILED]\x1b[0m"
#define TC_SKIP_STR "\x1b[1;30;103m[SKIPPED]\x1b[0m"
#define TC_FLAKY_STR "\x1b[1;30;105m[FLAKY]\x1b[0m"

#define TC_START_PRINT(name) printk("\x1b[2mSTART - %s \x1b[0m\n", name)

// Kill the ==== divider — verdict tags are enough visual separation.
/* #define PRINT_LINE \ */
/*   do { \ */
/*   } while (0) */

// "[PASSED] test_name (PASS - test_name in 0.006 seconds)"
//          ^-- green                ^-- dim (also the canonical sentinel that
// twister's ztest harness regex (.*(PASS|FAIL|SKIP) - \S+ in \d+ seconds)
// parses for per-test reporting in the twister.json/xunit reports).
#define Z_TC_END_RESULT(result, func)                                          \
  do {                                                                         \
    const char *name_color = (result) == TC_PASS   ? "\x1b[32m"                \
                             : (result) == TC_FAIL ? "\x1b[31m"                \
                             : (result) == TC_SKIP ? "\x1b[33m"                \
                                                   : "\x1b[35m";               \
    const char *canon = (result) == TC_PASS   ? "PASS"                         \
                        : (result) == TC_FAIL ? "FAIL"                         \
                        : (result) == TC_SKIP ? "SKIP"                         \
                                              : "FLAKY";                       \
    TC_END_PRINT(result,                                                       \
                 "%s %s%s\x1b[0m \x1b[2m(%s - %s in %u.%03u seconds)"          \
                 "\x1b[0m\n",                                                  \
                 TC_RESULT_TO_STR(result), name_color, func, canon, func,      \
                 tc_spend_time / 1000, tc_spend_time % 1000);                  \
  } while (0)

#endif
