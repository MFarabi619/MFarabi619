const c = @import("../c/bindings.zig").c;

pub fn set_locale() void {
    _ = c.setlocale(c.LC_ALL, "");
}

pub fn init() !void {
    if (c.bsddialog_init() == c.BSDDIALOG_ERROR) {
        return error.BSDDialogInitFailed;
    }
}

pub fn end() void {
    _ = c.bsddialog_end();
}

pub fn get_error() [*:0]const u8 {
    return c.bsddialog_geterror();
}
