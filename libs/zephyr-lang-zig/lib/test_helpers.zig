// Shared ztest assertion bridges. Implementations live in src/bridge.c
// (gated on CONFIG_ZTEST) so every test inherits them automatically via
// the ztest_app helper.

pub extern fn zig_assert_true(condition: bool) void;
pub extern fn zig_assert_i64_eq(actual: i64, expected: i64) void;
pub extern fn zig_assert_u32_eq(actual: u32, expected: u32) void;
pub extern fn zig_assert_usize_eq(actual: usize, expected: usize) void;
pub extern fn zig_assert_not_null(p: *const anyopaque) void;
pub extern fn zig_assert_unreachable() noreturn;

// `zig_assume_*`: like zig_assert_* but on failure the test is SKIPPED
// (not failed). Use for prerequisite checks ("this test only makes sense
// if X is true") so platform-conditional tests register as skipped, not
// false failures.
pub extern fn zig_assume_true(condition: bool) void;
pub extern fn zig_assume_i64_eq(actual: i64, expected: i64) void;
