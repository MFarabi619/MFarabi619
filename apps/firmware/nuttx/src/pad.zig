const std = @import("std");

pub const Command = struct {
    linear: i8,
    angular: i8,
};

pub const Cell = struct {
    dx: i8,
    dy: i8,
    key: u8,
    is_stop: bool,
    is_active: bool,
};

const keys = [3][3]u8{
    .{ 'u', 'i', 'o' },
    .{ 'j', 'k', 'l' },
    .{ 'm', ',', '.' },
};

pub fn cells(linear: i8, angular: i8) [3][3]Cell {
    var grid: [3][3]Cell = undefined;
    const active_row = 1 - linear;
    const active_col = 1 - angular;
    for (0..3) |row| {
        for (0..3) |col| {
            const r: i8 = @intCast(row);
            const co: i8 = @intCast(col);
            grid[row][col] = .{
                .dx = co - 1,
                .dy = r - 1,
                .key = keys[row][col],
                .is_stop = row == 1 and col == 1,
                .is_active = r == active_row and co == active_col,
            };
        }
    }
    return grid;
}

pub fn arrowGlyph(dx: i8, dy: i8) []const u8 {
    return switch (dy) {
        -1 => switch (dx) {
            -1 => "\u{2196}",
            1 => "\u{2197}",
            else => "\u{2191}",
        },
        1 => switch (dx) {
            -1 => "\u{2199}",
            1 => "\u{2198}",
            else => "\u{2193}",
        },
        else => switch (dx) {
            -1 => "\u{2190}",
            1 => "\u{2192}",
            else => "\u{25CB}",
        },
    };
}

pub fn keyCommand(ch: u21) ?Command {
    if (ch > 127) return null;
    const lower = std.ascii.toLower(@intCast(ch));
    for (keys, 0..) |row_keys, row| {
        for (row_keys, 0..) |k, col| {
            if (k == lower) {
                return .{
                    .linear = 1 - @as(i8, @intCast(row)),
                    .angular = 1 - @as(i8, @intCast(col)),
                };
            }
        }
    }
    return null;
}
