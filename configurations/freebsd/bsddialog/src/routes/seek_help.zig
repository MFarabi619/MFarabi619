const messages = @import("messages.zig");

pub fn run() !void {
    try messages.show(.{
        .title = "❓ Seek Help",
        .text =
            "Need help?\n\n"
            ++ "- Handbook: https://docs.freebsd.org/en/books/handbook/\n"
            ++ "- DoomBSD Docs: No gods. No tech support. Only source code.\n"
            ++ "- Community: Nonexistent :/",
        .rows = 12,
        .cols = 60,
    });
}
