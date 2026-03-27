const c = @import("../c/bindings.zig").c;

pub const Result = enum {
    ok,
    cancel,
    help,
    extra,
    timeout,
    esc,
    @"error",
    unknown,
};

pub fn from_dialog_output(output: c_int) Result {
    return switch (output) {
        c.BSDDIALOG_OK => .ok,
        c.BSDDIALOG_CANCEL => .cancel,
        c.BSDDIALOG_HELP => .help,
        c.BSDDIALOG_EXTRA => .extra,
        c.BSDDIALOG_TIMEOUT => .timeout,
        c.BSDDIALOG_ESC => .esc,
        c.BSDDIALOG_ERROR => .@"error",
        else => .unknown,
    };
}

test "maps known dialog outputs" {
    try std.testing.expectEqual(Result.ok, from_dialog_output(c.BSDDIALOG_OK));
    try std.testing.expectEqual(Result.cancel, from_dialog_output(c.BSDDIALOG_CANCEL));
    try std.testing.expectEqual(Result.help, from_dialog_output(c.BSDDIALOG_HELP));
    try std.testing.expectEqual(Result.extra, from_dialog_output(c.BSDDIALOG_EXTRA));
    try std.testing.expectEqual(Result.timeout, from_dialog_output(c.BSDDIALOG_TIMEOUT));
    try std.testing.expectEqual(Result.esc, from_dialog_output(c.BSDDIALOG_ESC));
    try std.testing.expectEqual(Result.@"error", from_dialog_output(c.BSDDIALOG_ERROR));
}

test "maps unknown dialog outputs" {
    try std.testing.expectEqual(Result.unknown, from_dialog_output(42));
}

const std = @import("std");
