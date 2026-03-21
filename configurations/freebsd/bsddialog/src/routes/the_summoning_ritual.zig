const std = @import("std");
const messages = @import("messages.zig");
const dry_run_installer = @import("../dry_run_installer.zig");

const c = @import("../c/bindings.zig").c;
const session = @import("../bsddialog/session.zig");

const dialog_rows: c_int = 26;
const dialog_cols: c_int = 96;

pub const TheSummoningRitualResult = struct {
    output: c_int,
    selected: []const u8,
};

pub fn run(selected_output_buffer: []u8) !TheSummoningRitualResult {
    var conf: c.struct_bsddialog_conf = undefined;
    messages.init_cli_like_conf(&conf);
    conf.title = " The Summoning Ritual";
    conf.bottomtitle = "• ↔ move • ⇥ TAB • ↵ ENTER •";
    conf.auto_topmargin = 2;
    conf.menu.no_desc = true;

    c.bsddialog_clear(0);
    _ = c.bsddialog_backtitle_rf(&conf, "DoomBSD Catacombs");

    var programs_separator = [_]c.struct_bsddialog_menuitem{
        .{ .name = "Programs", .desc = "", .on = true, .depth = 0, .prefix = "", .bottomdesc = "" },
    };
    var programs_items = [_]c.struct_bsddialog_menuitem{
        .{ .name = "hyprland (HyDE)", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
        .{ .name = "dbus", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
        .{ .name = "xdg-desktop-portal", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
        .{ .name = "wayland", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
        .{ .name = "xwayland", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
    };

    var editor_separator = [_]c.struct_bsddialog_menuitem{
        .{ .name = "Editors", .desc = "", .on = true, .depth = 0, .prefix = "", .bottomdesc = "" },
    };
    var editor_items = [_]c.struct_bsddialog_menuitem{
        .{ .name = "neovim", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
        .{ .name = "py311-pynvim", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
        .{ .name = "emacs", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
    };

    var fonts_separator = [_]c.struct_bsddialog_menuitem{
        .{ .name = "Fonts", .desc = "", .on = true, .depth = 0, .prefix = "", .bottomdesc = "" },
    };
    var fonts_items = [_]c.struct_bsddialog_menuitem{
        .{ .name = "jetbrains-mono", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
        .{ .name = "nerd-fonts", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
        .{ .name = "noto-emoji", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
    };

    var tools_separator = [_]c.struct_bsddialog_menuitem{
        .{ .name = "Tools", .desc = "", .on = true, .depth = 0, .prefix = "", .bottomdesc = "" },
    };
    var tools_items = [_]c.struct_bsddialog_menuitem{
        .{ .name = "git", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
        .{ .name = "direnv", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
        .{ .name = "ripgrep", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
        .{ .name = "ripgrep-all", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
        .{ .name = "bat", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
        .{ .name = "fzf", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
        .{ .name = "yazi", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
        .{ .name = "tree", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
        .{ .name = "eza", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
        .{ .name = "vips", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
        .{ .name = "term", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
    };

    programs_items[0].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .the_summoning_ritual, programs_items[0].name, &.{"Hyprland"});
    programs_items[1].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .the_summoning_ritual, programs_items[1].name, &.{"dbus-daemon"});
    programs_items[2].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .the_summoning_ritual, programs_items[2].name, &.{"xdg-desktop-portal"});
    programs_items[3].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .the_summoning_ritual, programs_items[3].name, &.{"wayland-scanner"});
    programs_items[4].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .the_summoning_ritual, programs_items[4].name, &.{"Xwayland"});

    editor_items[0].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .the_summoning_ritual, editor_items[0].name, &.{"nvim"});
    editor_items[1].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .the_summoning_ritual, editor_items[1].name, &.{"python3"});
    editor_items[2].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .the_summoning_ritual, editor_items[2].name, &.{"emacs"});

    fonts_items[0].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .the_summoning_ritual, fonts_items[0].name, &.{});
    fonts_items[1].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .the_summoning_ritual, fonts_items[1].name, &.{});
    fonts_items[2].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .the_summoning_ritual, fonts_items[2].name, &.{});

    tools_items[0].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .the_summoning_ritual, tools_items[0].name, &.{"git"});
    tools_items[1].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .the_summoning_ritual, tools_items[1].name, &.{"direnv"});
    tools_items[2].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .the_summoning_ritual, tools_items[2].name, &.{"rg"});
    tools_items[3].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .the_summoning_ritual, tools_items[3].name, &.{"rga"});
    tools_items[4].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .the_summoning_ritual, tools_items[4].name, &.{"bat"});
    tools_items[5].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .the_summoning_ritual, tools_items[5].name, &.{"fzf"});
    tools_items[6].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .the_summoning_ritual, tools_items[6].name, &.{"yazi"});
    tools_items[7].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .the_summoning_ritual, tools_items[7].name, &.{"tree"});
    tools_items[8].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .the_summoning_ritual, tools_items[8].name, &.{"eza"});
    tools_items[9].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .the_summoning_ritual, tools_items[9].name, &.{"vips"});
    tools_items[10].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .the_summoning_ritual, tools_items[10].name, &.{"kitty"});

    var groups = [_]c.struct_bsddialog_menugroup{
        .{ .type = c.BSDDIALOG_SEPARATOR, .nitems = programs_separator.len, .items = &programs_separator[0], .min_on = 0 },
        .{ .type = c.BSDDIALOG_CHECKLIST, .nitems = programs_items.len, .items = &programs_items[0], .min_on = 0 },
        .{ .type = c.BSDDIALOG_SEPARATOR, .nitems = editor_separator.len, .items = &editor_separator[0], .min_on = 0 },
        .{ .type = c.BSDDIALOG_CHECKLIST, .nitems = editor_items.len, .items = &editor_items[0], .min_on = 0 },
        .{ .type = c.BSDDIALOG_SEPARATOR, .nitems = fonts_separator.len, .items = &fonts_separator[0], .min_on = 0 },
        .{ .type = c.BSDDIALOG_CHECKLIST, .nitems = fonts_items.len, .items = &fonts_items[0], .min_on = 0 },
        .{ .type = c.BSDDIALOG_SEPARATOR, .nitems = tools_separator.len, .items = &tools_separator[0], .min_on = 0 },
        .{ .type = c.BSDDIALOG_CHECKLIST, .nitems = tools_items.len, .items = &tools_items[0], .min_on = 0 },
    };

    const output = c.bsddialog_mixedlist(
        &conf,
        "Here in the chamber, unseen daemons stir beneath the surface... shaping the destiny of your system.",
        dialog_rows,
        dialog_cols,
        18,
        groups.len,
        &groups,
        null,
        null,
    );
    if (output == c.BSDDIALOG_ERROR) {
        std.debug.print("Error: {s}\n", .{session.get_error()});
        return error.BSDDialogMixedListFailed;
    }

    if (output != c.BSDDIALOG_OK) {
        return .{ .output = output, .selected = "" };
    }

    const selected = try serialize_selected_from_groups(selected_output_buffer, &.{ programs_items[0..], editor_items[0..], fonts_items[0..], tools_items[0..] });
    return .{ .output = output, .selected = selected };
}

fn serialize_selected_from_groups(output_buffer: []u8, groups: []const []const c.struct_bsddialog_menuitem) ![]const u8 {
    var fixed_buffer_stream = std.io.fixedBufferStream(output_buffer);
    const writer = fixed_buffer_stream.writer();

    var is_first_item = true;
    for (groups) |group_items| {
        for (group_items) |item| {
            if (!item.on) continue;
            const item_name = std.mem.span(item.name);
            if (!is_first_item) {
                try writer.writeByte(' ');
            }
            is_first_item = false;

            const item_has_space = std.mem.indexOfScalar(u8, item_name, ' ') != null;
            if (item_has_space) try writer.writeByte('"');
            try writer.writeAll(item_name);
            if (item_has_space) try writer.writeByte('"');
        }
    }

    return fixed_buffer_stream.getWritten();
}
