extern fn zig_assert_true(condition: bool) void;
extern fn zig_assert_i64_eq(actual: i64, expected: i64) void;
extern fn zig_assert_u32_eq(actual: u32, expected: u32) void;
extern fn zig_assert_usize_eq(actual: usize, expected: usize) void;
extern fn zig_assert_not_null(pointer: *const anyopaque) void;
extern fn zig_assert_unreachable() noreturn;

pub fn eq(actual: anytype, expected: anytype) void {
    const T = @TypeOf(actual, expected);
    switch (@typeInfo(T)) {
        .int => |info| {
            if (info.signedness == .signed) {
                zig_assert_i64_eq(@as(i64, actual), @as(i64, expected));
            } else if (info.bits <= 32) {
                zig_assert_u32_eq(@as(u32, actual), @as(u32, expected));
            } else {
                zig_assert_usize_eq(@as(usize, actual), @as(usize, expected));
            }
        },
        .comptime_int => zig_assert_i64_eq(@as(i64, actual), @as(i64, expected)),
        .bool => zig_assert_true(actual == expected),
        else => @compileError("assert.eq: unsupported type " ++ @typeName(T)),
    }
}

pub fn isTrue(condition: bool) void {
    zig_assert_true(condition);
}

pub fn notNull(pointer: anytype) void {
    zig_assert_not_null(@ptrCast(pointer));
}

pub fn unreached() noreturn {
    zig_assert_unreachable();
}
