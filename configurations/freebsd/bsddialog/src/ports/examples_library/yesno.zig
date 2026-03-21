const std = @import("std");
const doombsd = @import("../../root.zig");

const session = doombsd.session;
const types = doombsd.types;
const yesno_widget = doombsd.widgets.yesno;

pub fn run() !void {
    var output: types.Result = undefined;
    var conf: doombsd.c.struct_bsddialog_conf = undefined;

    session.set_locale();

    session.init() catch {
        std.debug.print("Error: {s}\n", .{session.get_error()});
        return error.BSDDialogInitFailed;
    };
    defer session.end();

    output = try yesno_widget.show(&conf, .{
        .title = "yesno",
        .text = "Example",
        .rows = 7,
        .cols = 25,
    });

    switch (output) {
        .@"error" => {
            std.debug.print("Error {s}\n", .{session.get_error()});
            return error.BSDDialogYesNoFailed;
        },
        .ok => {
            std.debug.print("[YES]\n", .{});
        },
        .cancel => {
            std.debug.print("[NO]\n", .{});
        },
        else => {
            return error.UnexpectedBSDDialogResult;
        },
    }
}
