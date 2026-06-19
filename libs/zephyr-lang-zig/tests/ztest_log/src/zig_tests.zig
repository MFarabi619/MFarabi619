const std = @import("std");
const zephyr = @import("zephyr");
const t = @import("test_helpers");

const LOG_LEVEL_ERR: c_int = 1;
const LOG_LEVEL_WRN: c_int = 2;
const LOG_LEVEL_INF: c_int = 3;
const LOG_LEVEL_DBG: c_int = 4;

var captured_level: c_int = 0;
var captured_msg: [256]u8 = .{0} ** 256;
var captured_msg_len: usize = 0;

fn captureLogFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime fmt: []const u8,
    args: anytype,
) void {
    const prefix = "[" ++ @tagName(scope) ++ "] ";
    const formatted = std.fmt.bufPrintZ(&captured_msg, prefix ++ fmt, args) catch {
        captured_msg_len = 0;
        return;
    };
    captured_msg_len = formatted.len;
    captured_level = switch (level) {
        .err => LOG_LEVEL_ERR,
        .warn => LOG_LEVEL_WRN,
        .info => LOG_LEVEL_INF,
        .debug => LOG_LEVEL_DBG,
    };
    zephyr.logFn(level, scope, fmt, args);
}

pub const std_options: std.Options = .{
    .log_level = .debug,
    .logFn = captureLogFn,
};

const log = std.log.scoped(.zig_test);

fn last_msg_contains(needle: []const u8) bool {
    return std.mem.indexOf(u8, captured_msg[0..captured_msg_len], needle) != null;
}

export fn zig_before() void {
    captured_level = 0;
    captured_msg_len = 0;
}

export fn zig_test_log_info_dispatches() void {
    log.info("hello {d}", .{42});
    t.zig_assert_i64_eq(captured_level, LOG_LEVEL_INF);
    t.zig_assert_true(last_msg_contains("hello 42"));
}

export fn zig_test_log_warn_dispatches() void {
    log.warn("careful {d}", .{1});
    t.zig_assert_i64_eq(captured_level, LOG_LEVEL_WRN);
}

export fn zig_test_log_err_dispatches() void {
    log.err("oops {d}", .{99});
    t.zig_assert_i64_eq(captured_level, LOG_LEVEL_ERR);
}

export fn zig_test_log_debug_dispatches() void {
    log.debug("verbose {d}", .{0});
    t.zig_assert_i64_eq(captured_level, LOG_LEVEL_DBG);
}

export fn zig_test_log_scope_prefixed() void {
    const custom = std.log.scoped(.custom_scope);
    custom.info("ping", .{});
    t.zig_assert_true(last_msg_contains("[custom_scope]"));
    t.zig_assert_true(last_msg_contains("ping"));
}

export fn zig_test_log_format_args() void {
    log.info("multi {d} {s} {x}", .{ 7, "args", @as(u32, 0xCAFE) });
    t.zig_assert_true(last_msg_contains("multi 7 args cafe"));
}
