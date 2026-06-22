#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#include <zephyr/kernel.h>
#include <zephyr/ztest.h>

void zig_assert_true(bool condition)
{
	zassert_true(condition, "expected true");
}

void zig_assert_i64_eq(int64_t actual, int64_t expected)
{
	zassert_equal(actual, expected, "expected %lld got %lld", (long long)expected,
		      (long long)actual);
}

void zig_assert_u32_eq(uint32_t actual, uint32_t expected)
{
	zassert_equal(actual, expected, "expected %u got %u", (unsigned int)expected,
		      (unsigned int)actual);
}

void zig_assert_usize_eq(size_t actual, size_t expected)
{
	zassert_equal(actual, expected, "expected %zu got %zu", expected, actual);
}

void zig_assert_not_null(const void *pointer)
{
	zassert_not_null(pointer, "expected non-null pointer");
}

FUNC_NORETURN void zig_assert_unreachable(void)
{
	zassert_unreachable("control reached an `unreachable` path from Zig");
	CODE_UNREACHABLE;
}
