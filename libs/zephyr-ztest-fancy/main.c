#include <stdint.h>

#include <zephyr/sys/printk.h>
#include <zephyr/ztest.h>

void test_main(void) {
  ztest_run_all(NULL, false, 1, 1);
  ztest_verify_all_test_suites_ran();

  int failed = 0;
  STRUCT_SECTION_FOREACH(ztest_unit_test, test) {
    if (test->stats != NULL && test->stats->fail_count > 0) {
      failed++;
    }
  }

  TC_END_REPORT(failed > 0 ? TC_FAIL : TC_PASS);

  // Exit QEMU via the SiFive test finisher at 0x100000 (same write
  // Zephyr's z_sys_poweroff() does for this SoC). TC_END_POST isn't
  // #ifndef-wrapped in tc_util.h so we can't override it cleanly.
  *(volatile uint32_t *)0x100000 = 0x5555;
}
