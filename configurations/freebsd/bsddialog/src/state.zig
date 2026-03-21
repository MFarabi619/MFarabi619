const c = @import("c/bindings.zig").c;

pub const State = enum {
    main_menu,
    ui,
    the_summoning_ritual,
    extras,
    lore,
    seek_help,
    health,
    exit,
};

pub const DialogEvent = enum {
    ok,
    cancel,
    help_or_extra,
    unknown,
};

pub fn event_from_output(dialog_output: c_int) DialogEvent {
    return switch (dialog_output) {
        c.BSDDIALOG_OK => .ok,
        c.BSDDIALOG_CANCEL => .cancel,
        c.BSDDIALOG_HELP, c.BSDDIALOG_EXTRA => .help_or_extra,
        else => .unknown,
    };
}

pub fn route_from_menu_choice(menu_choice: u8) ?State {
    return switch (menu_choice) {
        'U' => .ui,
        'D' => .the_summoning_ritual,
        'X' => .extras,
        'L' => .lore,
        '?' => .seek_help,
        'H' => .health,
        else => null,
    };
}
