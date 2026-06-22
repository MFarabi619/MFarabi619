const std = @import("std");
const zephyr = @import("zephyr");
const assert = @import("test_helpers");

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
    zephyr.bdd.given("a scoped logger wired through zephyr.logFn");
    zephyr.bdd.when("log.info is called with a formatted argument");
    zephyr.bdd.then("captured level is INFO and the message contains the rendered value");

    log.info("hello {d}", .{42});
    assert.eq(captured_level, LOG_LEVEL_INF);
    assert.isTrue(last_msg_contains("hello 42"));
}

export fn zig_test_log_warn_dispatches() void {
    zephyr.bdd.given("a scoped logger");
    zephyr.bdd.when("log.warn is called");
    zephyr.bdd.then("captured level is WARN");

    log.warn("careful {d}", .{1});
    assert.eq(captured_level, LOG_LEVEL_WRN);
}

export fn zig_test_log_err_dispatches() void {
    zephyr.bdd.given("a scoped logger");
    zephyr.bdd.when("log.err is called");
    zephyr.bdd.then("captured level is ERR");

    log.err("oops {d}", .{99});
    assert.eq(captured_level, LOG_LEVEL_ERR);
}

export fn zig_test_log_debug_dispatches() void {
    zephyr.bdd.given("a scoped logger");
    zephyr.bdd.when("log.debug is called");
    zephyr.bdd.then("captured level is DBG");

    log.debug("verbose {d}", .{0});
    assert.eq(captured_level, LOG_LEVEL_DBG);
}

export fn zig_test_log_scope_prefixed() void {
    zephyr.bdd.given("a logger scoped to .custom_scope");
    zephyr.bdd.when("an info message is logged");
    zephyr.bdd.then("the captured payload begins with the scope tag");

    const custom = std.log.scoped(.custom_scope);
    custom.info("ping", .{});
    assert.isTrue(last_msg_contains("[custom_scope]"));
    assert.isTrue(last_msg_contains("ping"));
}

export fn zig_test_log_format_args() void {
    zephyr.bdd.given("a multi-argument log format string");
    zephyr.bdd.when("integer, string, and hex arguments are passed");
    zephyr.bdd.then("all three render in the captured message");

    log.info("multi {d} {s} {x}", .{ 7, "args", @as(u32, 0xCAFE) });
    assert.isTrue(last_msg_contains("multi 7 args cafe"));
}
