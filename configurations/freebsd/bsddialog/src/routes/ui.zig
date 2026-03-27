const std = @import("std");
const messages = @import("messages.zig");

const c = @import("../c/bindings.zig").c;
const session = @import("../bsddialog/session.zig");

const dialog_rows: c_int = 26;
const dialog_cols: c_int = 96;

pub const ThemeChoice = enum {
    doom,
    orangey_black,
    black_white,
};

pub const UiResult = struct {
    output: c_int,
    selected_theme: ?ThemeChoice,
};

pub fn run(current_theme: ThemeChoice) !UiResult {
    var conf: c.struct_bsddialog_conf = undefined;
    messages.init_cli_like_conf(&conf);
    conf.title = "❖ UI";
    conf.auto_topmargin = 2;

    c.bsddialog_clear(0);
    _ = c.bsddialog_backtitle_rf(&conf, " DoomBSD Catacombs");

    var items = [_]c.struct_bsddialog_menuitem{
        .{ .name = "D", .desc = "Red", .bottomdesc = "The default hellfire DoomBSD style.", .on = current_theme == .doom, .depth = 0, .prefix = "" },
        .{ .name = "O", .desc = "Orange/Black", .bottomdesc = "A black background with warm orange accents.", .on = current_theme == .orangey_black, .depth = 0, .prefix = "" },
        .{ .name = "B", .desc = "Black & White", .bottomdesc = "Default BlackWhite theme like examples_library/theme.c.", .on = current_theme == .black_white, .depth = 0, .prefix = "" },
    };

    const output = c.bsddialog_radiolist(
        &conf,
        "Choose the UI theme.",
        dialog_rows,
        dialog_cols,
        6,
        items.len,
        &items,
        null,
    );
    if (output == c.BSDDIALOG_ERROR) {
        std.debug.print("Error: {s}\n", .{session.get_error()});
        return error.BSDDialogMenuFailed;
    }

    if (items[0].on) {
        return .{ .output = output, .selected_theme = .doom };
    }
    if (items[1].on) {
        return .{ .output = output, .selected_theme = .orangey_black };
    }
    if (items[2].on) {
        return .{ .output = output, .selected_theme = .black_white };
    }

    return .{ .output = output, .selected_theme = null };
}
