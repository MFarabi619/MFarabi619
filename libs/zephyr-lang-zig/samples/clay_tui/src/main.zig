const zephyr = @import("zephyr");
const clay = @import("zclay");

pub const panic = zephyr.panic;

var clay_arena: [128 * 1024]u8 align(16) = undefined;

const layout_width: f32 = 80;
const layout_height: f32 = 24;
const grid_w: usize = 80;
const grid_h: usize = 24;

// Gruvbox dark hard.
const bg0: clay.Color = .{ 29, 32, 33, 255 };
const bg1: clay.Color = .{ 60, 56, 54, 255 };
const bg2: clay.Color = .{ 80, 73, 69, 255 };
const fg1: clay.Color = .{ 235, 219, 178, 255 };
const fg4: clay.Color = .{ 168, 153, 132, 255 };
const gray: clay.Color = .{ 146, 131, 116, 255 };
const yellow: clay.Color = .{ 250, 189, 47, 255 };
const orange: clay.Color = .{ 254, 128, 25, 255 };
const aqua: clay.Color = .{ 142, 192, 124, 255 };
const blue: clay.Color = .{ 131, 165, 152, 255 };

// Reusable text configs.
const TextCfg = clay.TextElementConfig;
const t_title: TextCfg = .{ .color = orange, .font_size = 1 };
const t_label: TextCfg = .{ .color = yellow, .font_size = 1 };
const t_value: TextCfg = .{ .color = fg1, .font_size = 1 };
const t_dim: TextCfg = .{ .color = gray, .font_size = 1 };
const t_muted: TextCfg = .{ .color = fg4, .font_size = 1 };
const t_link: TextCfg = .{ .color = blue, .font_size = 1 };
const t_ok: TextCfg = .{ .color = aqua, .font_size = 1 };

const spaces: [80]u8 = .{' '} ** 80;

// Box-drawing grid: each cell tracks which of its 4 edges are "occupied" by
// a border segment, plus the color to paint the resulting char in. We collect
// edge bits per cell during BORDER command processing, then resolve each cell
// to a single Unicode char that satisfies all of its edges (so T-junctions
// and crosses come out right where multiple borders meet).
const EDGE_TOP: u8 = 1;
const EDGE_RIGHT: u8 = 2;
const EDGE_BOTTOM: u8 = 4;
const EDGE_LEFT: u8 = 8;

const BoxCell = struct { flags: u8 = 0, color: clay.Color = .{ 0, 0, 0, 0 } };
var box_grid: [grid_h][grid_w]BoxCell = undefined;

const box_chars = blk: {
    var arr: [16][]const u8 = .{""} ** 16;
    arr[EDGE_TOP] = "╵";
    arr[EDGE_RIGHT] = "╶";
    arr[EDGE_BOTTOM] = "╷";
    arr[EDGE_LEFT] = "╴";
    arr[EDGE_TOP | EDGE_RIGHT] = "└";
    arr[EDGE_TOP | EDGE_BOTTOM] = "│";
    arr[EDGE_TOP | EDGE_LEFT] = "┘";
    arr[EDGE_RIGHT | EDGE_BOTTOM] = "┌";
    arr[EDGE_RIGHT | EDGE_LEFT] = "─";
    arr[EDGE_BOTTOM | EDGE_LEFT] = "┐";
    arr[EDGE_TOP | EDGE_RIGHT | EDGE_BOTTOM] = "├";
    arr[EDGE_TOP | EDGE_RIGHT | EDGE_LEFT] = "┴";
    arr[EDGE_TOP | EDGE_BOTTOM | EDGE_LEFT] = "┤";
    arr[EDGE_RIGHT | EDGE_BOTTOM | EDGE_LEFT] = "┬";
    arr[EDGE_TOP | EDGE_RIGHT | EDGE_BOTTOM | EDGE_LEFT] = "┼";
    break :blk arr;
};

fn boxClear() void {
    for (&box_grid) |*row| {
        for (row) |*cell| cell.* = .{};
    }
}

fn boxAdd(x: i32, y: i32, edges: u8, color: clay.Color) void {
    if (x < 0 or y < 0 or x >= grid_w or y >= grid_h) return;
    const ux: usize = @intCast(x);
    const uy: usize = @intCast(y);
    box_grid[uy][ux].flags |= edges;
    box_grid[uy][ux].color = color;
}

fn measureText(s: []const u8, _: *clay.TextElementConfig, _: void) clay.Dimensions {
    return .{ .w = @floatFromInt(s.len), .h = 1 };
}

fn errorHandler(_: clay.ErrorData) callconv(.c) void {
    @panic("clay layout error");
}

fn renderRect(x: i32, y: i32, w: i32, h: i32, color: clay.Color) void {
    // Skip fully-transparent rects (spacer elements default to {0,0,0,0}).
    if (color[3] == 0 or w <= 0 or h <= 0) return;
    const width_u: usize = @intCast(w);
    const span = spaces[0..@min(width_u, spaces.len)];
    const r: c_int = @intFromFloat(color[0]);
    const g: c_int = @intFromFloat(color[1]);
    const b: c_int = @intFromFloat(color[2]);
    var row: i32 = 0;
    while (row < h) : (row += 1) {
        zephyr.print("\x1b[{d};{d}H\x1b[48;2;{d};{d};{d}m{s}", .{
            y + row + 1, x + 1, r, g, b, span,
        });
    }
}

fn renderText(x: i32, y: i32, slice: []const u8, fg: clay.Color, bg: clay.Color) void {
    const fr: c_int = @intFromFloat(fg[0]);
    const fg_g: c_int = @intFromFloat(fg[1]);
    const fb: c_int = @intFromFloat(fg[2]);
    const br: c_int = @intFromFloat(bg[0]);
    const bgg: c_int = @intFromFloat(bg[1]);
    const bb: c_int = @intFromFloat(bg[2]);
    zephyr.print("\x1b[{d};{d}H\x1b[38;2;{d};{d};{d}m\x1b[48;2;{d};{d};{d}m{s}", .{
        y + 1, x + 1, fr, fg_g, fb, br, bgg, bb, slice,
    });
}

// Pre-grid pass: accumulate border edges into box_grid so intersections of
// multiple borders resolve to the right junction char.
fn accumulateBorder(x: i32, y: i32, w: i32, h: i32, width: clay.BorderWidth, color: clay.Color) void {
    // Top edge: horizontal run at y, from x to x+w-1.
    if (width.top > 0) {
        if (w >= 1) boxAdd(x, y, EDGE_RIGHT, color);
        var i: i32 = x + 1;
        while (i < x + w - 1) : (i += 1) boxAdd(i, y, EDGE_LEFT | EDGE_RIGHT, color);
        if (w >= 2) boxAdd(x + w - 1, y, EDGE_LEFT, color);
    }
    // Bottom edge.
    if (width.bottom > 0) {
        if (w >= 1) boxAdd(x, y + h - 1, EDGE_RIGHT, color);
        var i: i32 = x + 1;
        while (i < x + w - 1) : (i += 1) boxAdd(i, y + h - 1, EDGE_LEFT | EDGE_RIGHT, color);
        if (w >= 2) boxAdd(x + w - 1, y + h - 1, EDGE_LEFT, color);
    }
    // Left edge: vertical run at x, from y to y+h-1.
    if (width.left > 0) {
        if (h >= 1) boxAdd(x, y, EDGE_BOTTOM, color);
        var i: i32 = y + 1;
        while (i < y + h - 1) : (i += 1) boxAdd(x, i, EDGE_TOP | EDGE_BOTTOM, color);
        if (h >= 2) boxAdd(x, y + h - 1, EDGE_TOP, color);
    }
    // Right edge.
    if (width.right > 0) {
        if (h >= 1) boxAdd(x + w - 1, y, EDGE_BOTTOM, color);
        var i: i32 = y + 1;
        while (i < y + h - 1) : (i += 1) boxAdd(x + w - 1, i, EDGE_TOP | EDGE_BOTTOM, color);
        if (h >= 2) boxAdd(x + w - 1, y + h - 1, EDGE_TOP, color);
    }
}

fn flushBoxGrid(commands: []clay.RenderCommand) void {
    for (box_grid, 0..) |row, y| {
        for (row, 0..) |cell, x| {
            if (cell.flags == 0) continue;
            const chr = box_chars[cell.flags];
            if (chr.len == 0) continue;
            const fr: c_int = @intFromFloat(cell.color[0]);
            const fg_g: c_int = @intFromFloat(cell.color[1]);
            const fb: c_int = @intFromFloat(cell.color[2]);
            // Preserve underlying bg by looking it up from the rect commands.
            const bg = findBackgroundAt(commands, @floatFromInt(x), @floatFromInt(y)) orelse bg0;
            const br: c_int = @intFromFloat(bg[0]);
            const bgg: c_int = @intFromFloat(bg[1]);
            const bb: c_int = @intFromFloat(bg[2]);
            zephyr.print("\x1b[{d};{d}H\x1b[38;2;{d};{d};{d}m\x1b[48;2;{d};{d};{d}m{s}", .{
                y + 1, x + 1, fr, fg_g, fb, br, bgg, bb, chr,
            });
        }
    }
}

fn renderCommands(commands: []clay.RenderCommand) void {
    zephyr.say("\x1b[?25l\x1b[2J\x1b[H");
    renderRect(0, 0, @intFromFloat(layout_width), @intFromFloat(layout_height), bg0);

    // Pass 1: rectangles (panel backgrounds, between-children dividers).
    for (commands) |cmd| {
        if (cmd.command_type != .rectangle) continue;
        const bb = cmd.bounding_box;
        renderRect(
            @intFromFloat(bb.x),
            @intFromFloat(bb.y),
            @intFromFloat(bb.width),
            @intFromFloat(bb.height),
            cmd.render_data.rectangle.background_color,
        );
    }

    // Pass 2: borders → accumulate into box_grid, then flush as joined chars.
    boxClear();
    for (commands) |cmd| {
        if (cmd.command_type != .border) continue;
        const bb = cmd.bounding_box;
        const bd = cmd.render_data.border;
        accumulateBorder(
            @intFromFloat(bb.x),
            @intFromFloat(bb.y),
            @intFromFloat(bb.width),
            @intFromFloat(bb.height),
            bd.width,
            bd.color,
        );
    }
    flushBoxGrid(commands);

    // Pass 3: text on top of everything.
    for (commands) |cmd| {
        if (cmd.command_type != .text) continue;
        const bb = cmd.bounding_box;
        const td = cmd.render_data.text;
        const slice = td.string_contents.chars[0..@intCast(td.string_contents.length)];
        const bg = findBackgroundAt(commands, bb.x, bb.y) orelse bg0;
        renderText(@intFromFloat(bb.x), @intFromFloat(bb.y), slice, td.text_color, bg);
    }

    zephyr.print("\x1b[0m\x1b[{d};1H\x1b[?25h", .{@as(c_int, @intFromFloat(layout_height)) + 1});
}

fn findBackgroundAt(commands: []clay.RenderCommand, x: f32, y: f32) ?clay.Color {
    var i: usize = commands.len;
    while (i > 0) {
        i -= 1;
        const cmd = commands[i];
        if (cmd.command_type != .rectangle) continue;
        const rc = cmd.render_data.rectangle;
        if (rc.background_color[3] == 0) continue;
        const bb = cmd.bounding_box;
        if (x >= bb.x and x < bb.x + bb.width and y >= bb.y and y < bb.y + bb.height) {
            return rc.background_color;
        }
    }
    return null;
}

fn buildUI() void {
    clay.UI()(.{
        .id = .ID("Root"),
        .layout = .{
            .sizing = .grow,
            .direction = .top_to_bottom,
        },
        .background_color = bg0,
    })({
        // ===== HEADER =====
        clay.UI()(.{
            .id = .ID("Header"),
            .layout = .{
                .sizing = .{ .w = .grow, .h = .fixed(3) },
                .child_alignment = .{ .x = .center, .y = .center },
            },
            .background_color = bg2,
        })({
            clay.text("clay-tui", t_title);
        });

        // ===== BODY =====
        clay.UI()(.{
            .id = .ID("Body"),
            .layout = .{
                .sizing = .grow,
                .direction = .left_to_right,
            },
        })({
            // ----- Sidebar -----
            clay.UI()(.{
                .id = .ID("Sidebar"),
                .layout = .{
                    .sizing = .{ .w = .fixed(20), .h = .grow },
                    .direction = .top_to_bottom,
                    .padding = .{ .left = 2, .right = 2, .top = 1, .bottom = 1 },
                    .child_gap = 1,
                },
                .background_color = bg1,
            })({
                clay.text("STATUS", t_label);
                clay.text("running", t_ok);
                clay.text("80x24", t_value);
                clay.text("ansi 24-bit", t_value);

                clay.UI()(.{ .layout = .{ .sizing = .grow } })({});

                clay.text("EXIT", t_label);
                clay.text("Ctrl-A x", t_dim);
            });

            // ----- Content -----
            clay.UI()(.{
                .id = .ID("Content"),
                .layout = .{
                    .sizing = .grow,
                    .direction = .top_to_bottom,
                    .padding = .{ .left = 3, .right = 2, .top = 1, .bottom = 1 },
                    .child_gap = 1,
                },
            })({
                kv("target", "qemu_riscv32");
                kv("layout", "Clay v0.14");
                kv("render", "ANSI true-color");
                clay.UI()(.{ .layout = .{ .sizing = .{ .w = .grow, .h = .fixed(1) } } })({});
                kv("arena", "128 KB allocated");
                kv("used", "~82 KB (128 elem cap)");
            });
        });

        // ===== FOOTER =====
        clay.UI()(.{
            .id = .ID("Footer"),
            .layout = .{
                .sizing = .{ .w = .grow, .h = .fixed(1) },
                .padding = .{ .left = 2, .right = 2, .top = 0, .bottom = 0 },
                .child_gap = 1,
                .child_alignment = .{ .x = .left, .y = .center },
            },
            .background_color = bg2,
        })({
            clay.text("zephyr-lang-zig", t_link);
            clay.text("/", t_dim);
            clay.text("samples", t_muted);
            clay.text("/", t_dim);
            clay.text("clay_tui", t_title);
        });
    });
}

fn kv(label: []const u8, value: []const u8) void {
    clay.UI()(.{
        .layout = .{
            .sizing = .{ .w = .grow, .h = .fixed(1) },
            .direction = .left_to_right,
            .child_gap = 2,
        },
    })({
        // Right-align the label inside a fixed-width column for tabular look.
        clay.UI()(.{
            .layout = .{
                .sizing = .{ .w = .fixed(8), .h = .grow },
                .child_alignment = .{ .x = .right, .y = .center },
            },
        })({
            clay.text(label, t_label);
        });
        clay.text(value, t_value);
    });
}

fn app() !void {
    zephyr.say("clay-tui ready\n");

    clay.setMaxElementCount(128);
    clay.setMaxMeasureTextCacheWordCount(128);

    _ = clay.initialize(
        clay.Arena.init(clay_arena[0..]),
        .{ .w = layout_width, .h = layout_height },
        .{ .error_handler_function = errorHandler, .user_data = null },
    );
    clay.setMeasureTextFunction(void, {}, measureText);

    clay.setLayoutDimensions(.{ .w = layout_width, .h = layout_height });
    clay.beginLayout();
    buildUI();
    const cmds = clay.endLayout();
    renderCommands(cmds);

    while (true) try zephyr.sleepMs(60000);
}

export fn main() c_int {
    return zephyr.runApp(app);
}
