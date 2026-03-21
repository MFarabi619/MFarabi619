const std = @import("std");
const messages = @import("messages.zig");
const dry_run_installer = @import("../dry_run_installer.zig");

const c = @import("../c/bindings.zig").c;
const session = @import("../bsddialog/session.zig");

const dialog_rows: c_int = 26;
const dialog_cols: c_int = 96;

pub const ExtrasResult = struct {
    output: c_int,
    selected: []const u8,
};

pub fn run(selected_output_buffer: []u8) !ExtrasResult {
    var conf: c.struct_bsddialog_conf = undefined;
    messages.init_cli_like_conf(&conf);
    conf.title = "Extras: NixOS-like Modules";
    conf.bottomtitle = "• ↔ move • ⇥ TAB • ↵ ENTER •";
    conf.auto_topmargin = 2;
    conf.menu.no_desc = true;

    c.bsddialog_clear(0);
    _ = c.bsddialog_backtitle_rf(&conf, "DoomBSD Extras Configuration");

    var programs_separator = [_]c.struct_bsddialog_menuitem{
        .{ .name = "Programs", .desc = "", .on = true, .depth = 0, .prefix = "", .bottomdesc = "" },
    };
    var programs_items = [_]c.struct_bsddialog_menuitem{
        .{ .name = "fastfetch", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
        .{ .name = "lazygit", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
        .{ .name = "btop", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
        .{ .name = "zellij", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
        .{ .name = "television", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
    };

    var security_separator = [_]c.struct_bsddialog_menuitem{
        .{ .name = "Security", .desc = "", .on = true, .depth = 0, .prefix = "", .bottomdesc = "" },
    };
    var security_items = [_]c.struct_bsddialog_menuitem{
        .{ .name = "fail2ban", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
    };

    var services_separator = [_]c.struct_bsddialog_menuitem{
        .{ .name = "Services", .desc = "", .on = true, .depth = 0, .prefix = "", .bottomdesc = "" },
    };
    var services_items = [_]c.struct_bsddialog_menuitem{
        .{ .name = "caddy", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
        .{ .name = "openssh", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
    };

    var networking_separator = [_]c.struct_bsddialog_menuitem{
        .{ .name = "Networking", .desc = "", .on = true, .depth = 0, .prefix = "", .bottomdesc = "" },
    };
    var networking_items = [_]c.struct_bsddialog_menuitem{
        .{ .name = "tailscale", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
        .{ .name = "bmon", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
        .{ .name = "lazyssh", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
        .{ .name = "socat", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
        .{ .name = "websocat", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
    };

    var hardware_separator = [_]c.struct_bsddialog_menuitem{
        .{ .name = "Hardware", .desc = "", .on = true, .depth = 0, .prefix = "", .bottomdesc = "" },
    };
    var hardware_items = [_]c.struct_bsddialog_menuitem{
        .{ .name = "framework-system", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
        .{ .name = "framework-tool", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
        .{ .name = "framework-tool-tui", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
    };

    var virtualisation_separator = [_]c.struct_bsddialog_menuitem{
        .{ .name = "Virtualisation", .desc = "", .on = true, .depth = 0, .prefix = "", .bottomdesc = "" },
    };
    var virtualisation_items = [_]c.struct_bsddialog_menuitem{
        .{ .name = "docker", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
        .{ .name = "docker-compose", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
        .{ .name = "podman", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
        .{ .name = "kubernetes", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
    };

    var languages_separator = [_]c.struct_bsddialog_menuitem{
        .{ .name = "Languages", .desc = "", .on = true, .depth = 0, .prefix = "", .bottomdesc = "" },
    };
    var languages_items = [_]c.struct_bsddialog_menuitem{
        .{ .name = "rust", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
        .{ .name = "c", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
        .{ .name = "zig", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
        .{ .name = "python", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
        .{ .name = "ruby", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
        .{ .name = "go", .desc = "", .on = false, .depth = 0, .prefix = "", .bottomdesc = "" },
    };

    programs_items[0].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .extras, programs_items[0].name, &.{"fastfetch"});
    programs_items[1].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .extras, programs_items[1].name, &.{"lazygit"});
    programs_items[2].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .extras, programs_items[2].name, &.{"btop"});
    programs_items[3].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .extras, programs_items[3].name, &.{"zellij"});
    programs_items[4].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .extras, programs_items[4].name, &.{"television"});

    security_items[0].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .extras, security_items[0].name, &.{"fail2ban-client"});

    services_items[0].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .extras, services_items[0].name, &.{"caddy"});
    services_items[1].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .extras, services_items[1].name, &.{"ssh"});

    networking_items[0].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .extras, networking_items[0].name, &.{"tailscale"});
    networking_items[1].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .extras, networking_items[1].name, &.{"bmon"});
    networking_items[2].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .extras, networking_items[2].name, &.{"lazyssh"});
    networking_items[3].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .extras, networking_items[3].name, &.{"socat"});
    networking_items[4].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .extras, networking_items[4].name, &.{"websocat"});

    hardware_items[0].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .extras, hardware_items[0].name, &.{});
    hardware_items[1].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .extras, hardware_items[1].name, &.{"framework-tool"});
    hardware_items[2].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .extras, hardware_items[2].name, &.{"framework-tool"});

    virtualisation_items[0].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .extras, virtualisation_items[0].name, &.{"docker"});
    virtualisation_items[1].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .extras, virtualisation_items[1].name, &.{"docker-compose"});
    virtualisation_items[2].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .extras, virtualisation_items[2].name, &.{"podman"});
    virtualisation_items[3].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .extras, virtualisation_items[3].name, &.{"kubectl"});

    languages_items[0].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .extras, languages_items[0].name, &.{"rustc"});
    languages_items[1].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .extras, languages_items[1].name, &.{"cc"});
    languages_items[2].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .extras, languages_items[2].name, &.{"zig"});
    languages_items[3].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .extras, languages_items[3].name, &.{"python3"});
    languages_items[4].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .extras, languages_items[4].name, &.{"ruby"});
    languages_items[5].on = try dry_run_installer.is_item_selected_by_default(std.heap.c_allocator, .extras, languages_items[5].name, &.{"go"});

    var groups = [_]c.struct_bsddialog_menugroup{
        .{ .type = c.BSDDIALOG_SEPARATOR, .nitems = programs_separator.len, .items = &programs_separator[0], .min_on = 0 },
        .{ .type = c.BSDDIALOG_CHECKLIST, .nitems = programs_items.len, .items = &programs_items[0], .min_on = 0 },
        .{ .type = c.BSDDIALOG_SEPARATOR, .nitems = security_separator.len, .items = &security_separator[0], .min_on = 0 },
        .{ .type = c.BSDDIALOG_CHECKLIST, .nitems = security_items.len, .items = &security_items[0], .min_on = 0 },
        .{ .type = c.BSDDIALOG_SEPARATOR, .nitems = services_separator.len, .items = &services_separator[0], .min_on = 0 },
        .{ .type = c.BSDDIALOG_CHECKLIST, .nitems = services_items.len, .items = &services_items[0], .min_on = 0 },
        .{ .type = c.BSDDIALOG_SEPARATOR, .nitems = networking_separator.len, .items = &networking_separator[0], .min_on = 0 },
        .{ .type = c.BSDDIALOG_CHECKLIST, .nitems = networking_items.len, .items = &networking_items[0], .min_on = 0 },
        .{ .type = c.BSDDIALOG_SEPARATOR, .nitems = hardware_separator.len, .items = &hardware_separator[0], .min_on = 0 },
        .{ .type = c.BSDDIALOG_CHECKLIST, .nitems = hardware_items.len, .items = &hardware_items[0], .min_on = 0 },
        .{ .type = c.BSDDIALOG_SEPARATOR, .nitems = virtualisation_separator.len, .items = &virtualisation_separator[0], .min_on = 0 },
        .{ .type = c.BSDDIALOG_CHECKLIST, .nitems = virtualisation_items.len, .items = &virtualisation_items[0], .min_on = 0 },
        .{ .type = c.BSDDIALOG_SEPARATOR, .nitems = languages_separator.len, .items = &languages_separator[0], .min_on = 0 },
        .{ .type = c.BSDDIALOG_CHECKLIST, .nitems = languages_items.len, .items = &languages_items[0], .min_on = 0 },
    };

    const output = c.bsddialog_mixedlist(
        &conf,
        "Select optional setup modules:",
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

    const selected = try serialize_selected_from_groups(selected_output_buffer, &.{ programs_items[0..], security_items[0..], services_items[0..], networking_items[0..], hardware_items[0..], virtualisation_items[0..], languages_items[0..] });
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
