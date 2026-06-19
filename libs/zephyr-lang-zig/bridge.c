/*
 * C bridge for Zephyr APIs that are static inline in headers and therefore
 * not directly callable from Zig as extern symbols, plus the small adapter
 * surface that `zephyr.logFn` dispatches through and the shared ztest
 * assertion bridges every test calls into.
 *
 * With CONFIG_LOG=n the LOG_MODULE_REGISTER and LOG_* macros expand to
 * no-ops, so these functions still link cleanly — they just don't emit
 * anything. The assertion bridges are gated on CONFIG_ZTEST so non-test
 * builds don't pull in ztest.h.
 */

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#include <zephyr/drivers/gpio.h>
#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>

LOG_MODULE_REGISTER(zephyr_lang_zig, LOG_LEVEL_DBG);

unsigned int zig_sem_count(struct k_sem *sem)
{
	return k_sem_count_get(sem);
}

uint32_t zig_cycle_get_32(void)
{
	return sys_clock_cycle_get_32();
}

uint32_t zig_cycle_hz(void)
{
	return sys_clock_hw_cycles_per_sec();
}

bool zig_gpio_is_ready_dt(const struct gpio_dt_spec *spec)
{
	return gpio_is_ready_dt(spec);
}

int zig_gpio_pin_configure_dt(const struct gpio_dt_spec *spec, gpio_flags_t flags)
{
	return gpio_pin_configure_dt(spec, flags);
}

int zig_gpio_pin_toggle_dt(const struct gpio_dt_spec *spec)
{
	return gpio_pin_toggle_dt(spec);
}

void zig_log_err(const char *msg)
{
	LOG_ERR("%s", msg);
}

void zig_log_warn(const char *msg)
{
	LOG_WRN("%s", msg);
}

void zig_log_info(const char *msg)
{
	LOG_INF("%s", msg);
}

void zig_log_debug(const char *msg)
{
	LOG_DBG("%s", msg);
}

#ifdef CONFIG_ZTEST
#include <zephyr/ztest.h>

void zig_assert_true(bool condition)
{
	zassert_true(condition, "expected true");
}

void zig_assert_i64_eq(int64_t actual, int64_t expected)
{
	zassert_equal(actual, expected, "expected %lld got %lld",
		      (long long)expected, (long long)actual);
}

void zig_assert_u32_eq(uint32_t actual, uint32_t expected)
{
	zassert_equal(actual, expected, "expected %u got %u",
		      (unsigned int)expected, (unsigned int)actual);
}

void zig_assert_usize_eq(size_t actual, size_t expected)
{
	zassert_equal(actual, expected, "expected %zu got %zu",
		      expected, actual);
}

void zig_assert_not_null(const void *p)
{
	zassert_not_null(p, "expected non-null pointer");
}

FUNC_NORETURN void zig_assert_unreachable(void)
{
	zassert_unreachable("control reached an `unreachable` path from Zig");
	CODE_UNREACHABLE;
}

void zig_assume_true(bool condition)
{
	zassume_true(condition, "precondition failed");
}

void zig_assume_i64_eq(int64_t actual, int64_t expected)
{
	zassume_equal(actual, expected, "precondition: expected %lld got %lld",
		      (long long)expected, (long long)actual);
}
#endif /* CONFIG_ZTEST */
