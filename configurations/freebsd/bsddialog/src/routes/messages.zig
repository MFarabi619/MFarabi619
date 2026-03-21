const std = @import("std");
const c = @import("../c/bindings.zig").c;
const session = @import("../bsddialog/session.zig");

pub const Options = struct {
    title: ?[*:0]const u8 = null,
    text: [*:0]const u8,
    rows: c_int,
    cols: c_int,
};

pub fn show(options: Options) !void {
    var conf: c.struct_bsddialog_conf = undefined;
    init_cli_like_conf(&conf);
    conf.title = options.title;

    c.bsddialog_clear(0);
    const output = c.bsddialog_msgbox(&conf, options.text, options.rows, options.cols);
    if (output == c.BSDDIALOG_ERROR) {
        std.debug.print("Error: {s}\n", .{session.get_error()});
        return error.BSDDialogMsgBoxFailed;
    }
}

pub fn init_cli_like_conf(conf: *c.struct_bsddialog_conf) void {
    _ = c.bsddialog_initconf(conf);
    conf.key.enable_esc = true;
    conf.button.always_active = true;
    conf.menu.shortcut_buttons = true;
}
