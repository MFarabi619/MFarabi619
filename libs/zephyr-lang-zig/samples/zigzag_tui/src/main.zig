const std = @import("std");
const zephyr = @import("zephyr");
const zz = @import("zigzag");

pub const panic = zephyr.panic;

extern fn printk(fmt: [*:0]const u8, ...) void;

var render_buf: [128 * 1024]u8 = undefined;

// Gruvbox dark hard.
const orange = zz.Color.fromRgb(254, 128, 25);
const yellow = zz.Color.fromRgb(250, 189, 47);
const aqua = zz.Color.fromRgb(142, 192, 124);
const fg1 = zz.Color.fromRgb(235, 219, 178);
const fg4 = zz.Color.fromRgb(168, 153, 132);
const gray_c = zz.Color.fromRgb(146, 131, 116);
const blue = zz.Color.fromRgb(131, 165, 152);

// Inline ANSI helpers — embed colored fragments into a single content string
// so the outer Style.render() can fill the panel background uniformly.
fn lbl(a: std.mem.Allocator, text: []const u8) ![]const u8 {
    return (zz.Style{}).fg(yellow).render(a, text);
}
fn val(a: std.mem.Allocator, text: []const u8) ![]const u8 {
    return (zz.Style{}).fg(fg1).render(a, text);
}
fn dim(a: std.mem.Allocator, text: []const u8) ![]const u8 {
    return (zz.Style{}).fg(gray_c).render(a, text);
}

fn renderTUI(a: std.mem.Allocator) ![]const u8 {
    // === Title row above the panel ===
    const title = try (zz.Style{})
        .fg(orange)
        .bold(true)
        .width(64)
        .alignH(.center)
        .render(a, "zigzag-tui");

    // === Status line: STATUS · running · 80x24 · ansi 24-bit ===
    const sep = try dim(a, " · ");
    const status_running = try (zz.Style{}).fg(aqua).render(a, "running");
    const status_label = try (zz.Style{}).fg(yellow).bold(true).render(a, "STATUS");
    const status_dim_size = try val(a, "80x24");
    const status_dim_ansi = try val(a, "ansi 24-bit");
    const status_line = try std.fmt.allocPrint(a, "{s}{s}{s}{s}{s}{s}{s}", .{
        status_label, sep, status_running, sep, status_dim_size, sep, status_dim_ansi,
    });

    // === KV rows. Each line is a single string with inline styling so the
    // outer panel background fills the entire row uniformly.
    const rows = [_][]const u8{
        try kvLine(a, "target", "qemu_riscv32"),
        try kvLine(a, "layout", "ZigZag v0.1.2"),
        try kvLine(a, "render", "Style + join + ANSI"),
        "",
        try kvLine(a, "arena ", "128 KB allocated"),
        try kvLine(a, "alloc ", "FixedBufferAllocator"),
    };
    const kv_block = try zz.join.vertical(a, .left, &rows);

    // === Main bordered panel: title row on top, status line, divider, kv body
    const inner = try std.fmt.allocPrint(a, "{s}\n\n{s}\n\n{s}", .{ title, status_line, kv_block });
    const panel = try (zz.Style{})
        .borderAll(zz.Border.rounded)
        .borderForeground(orange)
        .padding(.{ .top = 1, .right = 2, .bottom = 1, .left = 2 })
        .width(72)
        .render(a, inner);

    // === Footer breadcrumb (single line, no border) ===
    const f_link = try (zz.Style{}).fg(blue).render(a, "zephyr-lang-zig");
    const f_sep = try (zz.Style{}).fg(gray_c).render(a, " / ");
    const f_mid = try (zz.Style{}).fg(fg4).render(a, "samples");
    const f_end = try (zz.Style{}).fg(orange).bold(true).render(a, "zigzag_tui");
    const footer = try std.fmt.allocPrint(a, "{s}{s}{s}{s}{s}", .{ f_link, f_sep, f_mid, f_sep, f_end });

    return zz.join.vertical(a, .center, &.{ panel, "", footer });
}

fn kvLine(a: std.mem.Allocator, label: []const u8, value: []const u8) ![]const u8 {
    const l = try lbl(a, label);
    const v = try val(a, value);
    return std.fmt.allocPrint(a, "{s}  {s}", .{ l, v });
}

fn app() !void {
    zephyr.say("zigzag-tui ready\n");

    var fba = std.heap.FixedBufferAllocator.init(&render_buf);
    const a = fba.allocator();

    const out = try renderTUI(a);
    const out_z = try a.dupeZ(u8, out);

    zephyr.say("\x1b[2J\x1b[H");
    printk("%s", out_z.ptr);
    zephyr.say("\n");

    while (true) try zephyr.sleepMs(60000);
}

export fn main() c_int {
    return zephyr.runApp(app);
}
