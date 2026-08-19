const std = @import("std");
const zz = @import("zigzag");
const Panel = @import("panel.zig").Panel;
const Touch = @import("touch.zig").Touch;
const pad = @import("pad.zig");

const c = @cImport({
    @cInclude("nuttx/config.h");
    @cInclude("unistd.h");
    @cInclude("poll.h");
    @cInclude("termios.h");
});

const arena_buffer_size = 32 * 1024;
var arena_buffer: [arena_buffer_size]u8 = undefined;

const gruvbox_cell_border = "#665c54";
const gruvbox_active_border = "#fe8019";
const gruvbox_arrow = "#ebdbb2";
const gruvbox_stop = "#fb4934";
const gruvbox_status = "#928374";

const Context = struct {
    allocator: std.mem.Allocator,
    width: u16 = 80,
    height: u16 = 24,
};

fn writeAll(bytes: []const u8) void {
    var offset: usize = 0;
    while (offset < bytes.len) {
        const written = c.write(c.STDOUT_FILENO, bytes.ptr + offset, bytes.len - offset);
        if (written <= 0) break;
        offset += @intCast(written);
    }
}

fn inputReady(timeout_ms: i32) bool {
    var poll_fds = [_]c.struct_pollfd{.{ .fd = c.STDIN_FILENO, .events = c.POLLIN, .revents = 0 }};
    return c.poll(&poll_fds, 1, timeout_ms) > 0 and (poll_fds[0].revents & c.POLLIN) != 0;
}

fn readByte() ?u8 {
    if (!inputReady(0)) return null;
    var byte: u8 = 0;
    if (c.read(c.STDIN_FILENO, &byte, 1) == 1) return byte;
    return null;
}

const RawMode = struct {
    saved_termios: c.struct_termios = undefined,
    active: bool = false,

    fn enter(self: *RawMode) void {
        if (c.tcgetattr(c.STDIN_FILENO, &self.saved_termios) != 0) return;
        var raw = self.saved_termios;
        const input_flags: c.tcflag_t = c.BRKINT | c.ICRNL | c.INPCK | c.ISTRIP | c.IXON;
        const local_flags: c.tcflag_t = c.ECHO | c.ICANON | c.IEXTEN | c.ISIG;
        raw.c_iflag &= ~input_flags;
        raw.c_oflag &= ~@as(c.tcflag_t, c.OPOST);
        raw.c_lflag &= ~local_flags;
        raw.c_cc[c.VMIN] = 0;
        raw.c_cc[c.VTIME] = 0;
        if (c.tcsetattr(c.STDIN_FILENO, c.TCSANOW, &raw) == 0) self.active = true;
    }

    fn leave(self: *RawMode) void {
        if (self.active) _ = c.tcsetattr(c.STDIN_FILENO, c.TCSANOW, &self.saved_termios);
    }
};

const Signal = enum { keep_running, quit };

const Model = struct {
    linear: i8 = 0,
    angular: i8 = 0,

    fn drive(self: *Model, linear: i8, angular: i8) void {
        self.linear = linear;
        self.angular = angular;
    }

    fn update(self: *Model, key: zz.KeyEvent) Signal {
        if (key.modifiers.ctrl) {
            switch (key.key) {
                .char => |ch| if (ch == 'c') return .quit,
                else => {},
            }
            return .keep_running;
        }
        switch (key.key) {
            .up => self.drive(1, 0),
            .down => self.drive(-1, 0),
            .left => self.drive(0, 1),
            .right => self.drive(0, -1),
            .char => |ch| {
                if (ch == 'q' or ch == 'Q') return .quit;
                if (pad.keyCommand(ch)) |cmd| self.drive(cmd.linear, cmd.angular);
            },
            else => {},
        }
        return .keep_running;
    }

    fn view(self: *const Model, ctx: *const Context) []const u8 {
        const grid = pad.cells(self.linear, self.angular);
        var pad_rows: [3][]const u8 = undefined;
        for (0..3) |row| {
            var row_cells: [3][]const u8 = undefined;
            for (0..3) |col| {
                row_cells[col] = renderCell(ctx, grid[row][col]) catch return "render error";
            }
            pad_rows[row] = zz.joinHorizontal(ctx.allocator, &.{ row_cells[0], " ", row_cells[1], " ", row_cells[2] }) catch return "render error";
        }
        const pad_view = zz.joinVertical(ctx.allocator, &.{ pad_rows[0], pad_rows[1], pad_rows[2] }) catch return "render error";
        return zz.placeHorizontal(ctx.allocator, ctx.width, .center, pad_view) catch pad_view;
    }
};

fn renderCell(ctx: *const Context, cell: pad.Cell) ![]const u8 {
    var glyph_style = zz.Style{};
    glyph_style = glyph_style.inline_style(true);
    glyph_style = glyph_style.fg(zz.Color.hex(if (cell.is_stop) gruvbox_stop else gruvbox_arrow));
    if (cell.is_active) glyph_style = glyph_style.bold(true);
    const glyph = try glyph_style.render(ctx.allocator, pad.arrowGlyph(cell.dx, cell.dy));

    var key_style = zz.Style{};
    key_style = key_style.inline_style(true);
    key_style = key_style.fg(zz.Color.hex(gruvbox_status));
    const key_text = [_]u8{cell.key};
    const key = try key_style.render(ctx.allocator, &key_text);

    const content = try zz.join.vertical(ctx.allocator, .center, &.{ glyph, key });

    var box = zz.Style{};
    box = box.borderAll(zz.Border.rounded);
    box = box.paddingLeft(2).paddingRight(2);
    box = box.borderForeground(zz.Color.hex(if (cell.is_active) gruvbox_active_border else gruvbox_cell_border));
    return box.render(ctx.allocator, content);
}

fn render(model: *const Model, ctx: *const Context, arena: *std.heap.FixedBufferAllocator) void {
    arena.reset();
    writeAll(zz.ansi.cursor_home);
    writeAll(model.view(ctx));
    writeAll(zz.ansi.screen_clear_below);
}

fn run() void {
    var raw = RawMode{};
    raw.enter();
    defer raw.leave();

    writeAll(zz.ansi.alt_screen_enter ++ zz.ansi.cursor_hide ++ zz.ansi.screen_clear ++ zz.ansi.cursor_home);
    defer writeAll(zz.ansi.cursor_show ++ zz.ansi.alt_screen_exit);

    var frame_arena = std.heap.FixedBufferAllocator.init(&arena_buffer);
    var ctx = Context{ .allocator = frame_arena.allocator() };
    var model = Model{};
    var input_buffer: [64]u8 = undefined;

    var panel: ?Panel = Panel.open() catch null;
    defer if (panel) |*p| p.close();

    var touch: ?Touch = Touch.open() catch null;
    defer if (touch) |*t| t.close();

    render(&model, &ctx, &frame_arena);
    if (panel) |*p| p.drawPad(model.linear, model.angular);
    while (true) {
        var poll_fds = [_]c.struct_pollfd{
            .{ .fd = c.STDIN_FILENO, .events = c.POLLIN, .revents = 0 },
            .{ .fd = if (touch) |t| t.fd else -1, .events = c.POLLIN, .revents = 0 },
        };
        _ = c.poll(&poll_fds, 2, -1);

        const before_linear = model.linear;
        const before_angular = model.angular;

        var input_len: usize = 0;
        while (readByte()) |byte| {
            if (input_len < input_buffer.len) {
                input_buffer[input_len] = byte;
                input_len += 1;
            }
        }
        var offset: usize = 0;
        while (offset < input_len) {
            const parsed = zz.input.keyboard.parse(input_buffer[offset..input_len]);
            if (parsed.consumed == 0) break;
            offset += parsed.consumed;
            switch (parsed.result) {
                .key => |key| switch (model.update(key)) {
                    .quit => return,
                    .keep_running => {},
                },
                else => {},
            }
        }

        if (touch) |*t| {
            while (t.read()) |event| {
                if (event.released) {
                    model.drive(0, 0);
                } else if (event.pressed) {
                    if (panel) |*p| {
                        if (p.hitTest(event.x, event.y)) |cmd| model.drive(cmd.linear, cmd.angular);
                    }
                }
            }
        }

        if (model.linear != before_linear or model.angular != before_angular) {
            render(&model, &ctx, &frame_arena);
            if (panel) |*p| p.drawPad(model.linear, model.angular);
        }
    }
}

export fn nuttx_zig_main(_: c_int, _: ?[*]const [*:0]u8) callconv(.c) c_int {
    run();
    return 0;
}
