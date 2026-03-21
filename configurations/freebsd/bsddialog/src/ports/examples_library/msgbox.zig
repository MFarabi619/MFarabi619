const std = @import("std");
const doombsd = @import("../../root.zig");

const session = doombsd.session;
const types = doombsd.types;
const msgbox_widget = doombsd.widgets.msgbox;

pub fn run() !void {
    var output: types.Result = undefined;
    var conf: doombsd.c.struct_bsddialog_conf = undefined;

    session.set_locale();

    session.init() catch {
        std.debug.print("Error: {s}\n", .{session.get_error()});
        return error.BSDDialogInitFailed;
    };
    defer session.end();

    output = try msgbox_widget.show(&conf, .{
        .title = "msgbox",
        .text = "Example",
        .rows = 7,
        .cols = 20,
    });

    switch (output) {
        .@"error" => {
            std.debug.print("Error {s}\n", .{session.get_error()});
            return error.BSDDialogMsgBoxFailed;
        },
        .ok => {
            std.debug.print("[OK]\n", .{});
        },
        else => {
            return error.UnexpectedBSDDialogResult;
        },
    }
}
