pub const c = @import("c/bindings.zig").c;

pub const state = @import("state.zig");
pub const loop = @import("loop.zig");
pub const theme = @import("theme.zig");
pub const dry_run_installer = @import("dry_run_installer.zig");

pub const types = @import("bsddialog/types.zig");
pub const session = @import("bsddialog/session.zig");

pub const routes = struct {
    pub const main_menu = @import("routes/main_menu.zig");
    pub const ui = @import("routes/ui.zig");
    pub const the_summoning_ritual = @import("routes/the_summoning_ritual.zig");
    pub const extras = @import("routes/extras.zig");
    pub const lore = @import("routes/lore.zig");
    pub const seek_help = @import("routes/seek_help.zig");
    pub const health = @import("routes/health.zig");
    pub const messages = @import("routes/messages.zig");
};

pub const shared = struct {
    pub const utils = @import("shared/utils.zig");
};

pub const widgets = struct {
    pub const infobox = @import("bsddialog/widgets/infobox.zig");
    pub const msgbox = @import("bsddialog/widgets/msgbox.zig");
    pub const yesno = @import("bsddialog/widgets/yesno.zig");
};

pub const examples_library = struct {
    pub const infobox = @import("ports/examples_library/infobox.zig");
    pub const msgbox = @import("ports/examples_library/msgbox.zig");
    pub const yesno = @import("ports/examples_library/yesno.zig");
};
