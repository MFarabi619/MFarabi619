const c = @import("../../c/bindings.zig").c;
const types = @import("../types.zig");

pub const Options = struct {
    title: ?[*:0]const u8 = null,
    text: [*:0]const u8,
    rows: c_int,
    cols: c_int,
    sleep: c_uint,
};

pub fn show(conf: *c.struct_bsddialog_conf, options: Options) !types.Result {
    _ = c.bsddialog_initconf(conf);
    conf.title = options.title;
    conf.sleep = options.sleep;

    const output = c.bsddialog_infobox(conf, options.text, options.rows, options.cols);
    return types.from_dialog_output(output);
}
