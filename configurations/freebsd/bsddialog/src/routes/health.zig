const messages = @import("messages.zig");

pub fn run() !void {
    try messages.show(.{
        .text = "There is no help here, return from whence you came.",
        .rows = 6,
        .cols = 60,
    });
}
