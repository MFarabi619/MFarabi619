const std = @import("std");
const messages = @import("messages.zig");

const c = @import("../c/bindings.zig").c;
const session = @import("../bsddialog/session.zig");

const dialog_rows: c_int = 20;
const dialog_cols: c_int = 60;

pub const MainMenuResult = struct {
    output: c_int,
    choice: ?u8,
};

pub fn run() !MainMenuResult {
    var conf: c.struct_bsddialog_conf = undefined;
    messages.init_cli_like_conf(&conf);
    conf.title = "󰇺 Main Menu";
    conf.button.ok_label = "PROCEED";
    conf.button.cancel_label = "FLEE";
    conf.button.with_help = true;
    conf.button.help_label = "HELP";
    conf.bottomtitle = "• ←→ move • ⇥ TAB • ↵ ENTER •";
    conf.auto_topmargin = 2;

    c.bsddialog_clear(0);
    _ = c.bsddialog_backtitle_rf(&conf, " DoomBSD Catacombs");

    var items = [_]c.struct_bsddialog_menuitem{
        .{ .name = "D", .desc = " The Summoning Ritual", .bottomdesc = "Tweak existing packages used by DoomBSD.", .on = false, .depth = 0, .prefix = "" },
        .{ .name = "X", .desc = "󰏗 Extras", .bottomdesc = "Experimental features not meant for mortals. You are already who you must become.", .on = false, .depth = 0, .prefix = "" },
        .{ .name = "L", .desc = " Lore", .bottomdesc = "Credits, inspirations, and heresies.", .on = false, .depth = 0, .prefix = "" },
        .{ .name = "?", .desc = " Seek Help", .bottomdesc = "Links to guides, or whatever remains of them.", .on = false, .depth = 0, .prefix = "" },
        .{ .name = "H", .desc = "󰊢 Health", .bottomdesc = "Check your temperature, fan the flames.", .on = false, .depth = 0, .prefix = "" },
        .{ .name = "U", .desc = "❖ UI", .bottomdesc = "Choose between Doom themes.", .on = false, .depth = 0, .prefix = "" },
    };

    const output = c.bsddialog_menu(
        &conf,
        "Welcome traveller, you have come not seeking peace... but madness, mayhem, and the cursed power of the Void.\n\nBe warned: this path leads only to insane efficiency, terminal sorcery, *exceptional* UNIX® grokking, and ultimate aesthetic overfunction.\n\nBegin the Rite of Configuration, ONLY IF YOU DARE!",
        dialog_rows,
        dialog_cols,
        8,
        items.len,
        &items,
        null,
    );
    if (output == c.BSDDIALOG_ERROR) {
        std.debug.print("Error: {s}\n", .{session.get_error()});
        return error.BSDDialogMenuFailed;
    }

    for (items) |item| {
        if (item.on) {
            const name = std.mem.span(item.name);
            if (name.len > 0) {
                return .{ .output = output, .choice = name[0] };
            }
        }
    }

    return .{ .output = output, .choice = null };
}
