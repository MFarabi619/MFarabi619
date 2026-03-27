const messages = @import("messages.zig");

pub fn run() !void {
    try messages.show(.{
        .title = "📖 THE LORE",
        .text =
            "DoomBSD draws inspiration from:\n\n"
            ++ "- Doom Emacs by Henrik Lissner\n"
            ++ "- HyDE Project\n"
            ++ "- ZaneyOS by Tyler Kelley\n"
            ++ "- LazyVim by Folke Lemaitre\n"
            ++ "- Lazygit by Jesse Duffield\n"
            ++ "- FreeBSD-SetupScript by es-j3\n"
            ++ "  https://github.com/es-j3/FreeBSD-SetupScript\n\n"
            ++ "A testament to those who dare dream deeper in dotfiles and the dark.",
        .rows = 20,
        .cols = 96,
    });
}
