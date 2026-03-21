const messages = @import("messages.zig");

pub fn run() !void {
    try messages.show(.{
        .title = "📖 THE LORE",
        .text =
            "DoomBSD draws inspiration from:\n\n"
            ++ "- Doom Emacs by Henrik Lissner\n"
            ++ "- HyDE Project\n"
            ++ "- ZaneyOS\n"
            ++ "- LazyVim\n"
            ++ "- FreeBSD-SetupScript by es-j3\n"
            ++ "  https://github.com/es-j3/FreeBSD-SetupScript\n\n"
            ++ "A testament to those who dare dream deeper in dotfiles and the dark.",
        .rows = 14,
        .cols = 70,
    });
}
