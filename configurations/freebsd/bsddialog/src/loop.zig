const std = @import("std");
const state_module = @import("state.zig");
const theme = @import("theme.zig");
const dry_run_installer = @import("dry_run_installer.zig");

const main_menu = @import("routes/main_menu.zig");
const ui = @import("routes/ui.zig");
const the_summoning_ritual = @import("routes/the_summoning_ritual.zig");
const extras = @import("routes/extras.zig");
const lore = @import("routes/lore.zig");
const seek_help = @import("routes/seek_help.zig");
const health = @import("routes/health.zig");
const messages = @import("routes/messages.zig");

const c = @import("c/bindings.zig").c;

pub fn run() !void {
    var current_state: state_module.State = .main_menu;
    var selected_output_buffer: [4096]u8 = undefined;
    var current_theme: ui.ThemeChoice = .doom;

    while (current_state != .exit) {
        switch (current_state) {
            .main_menu => {
                const menu_result = try main_menu.run();

                switch (state_module.event_from_output(menu_result.output)) {
                    .ok => {},
                    .cancel => {
                        try messages.show(.{
                            .text = "Cowardice detected. Fleeing the void...",
                            .rows = 6,
                            .cols = 50,
                        });
                        current_state = .exit;
                        continue;
                    },
                    .help_or_extra => {
                        try messages.show(.{
                            .text = "You take a moment to collect yourself... but the ritual remains unfinished.",
                            .rows = 6,
                            .cols = 50,
                        });
                        current_state = .main_menu;
                        continue;
                    },
                    .unknown => {
                        try messages.show(.{
                            .text = "Unknown signal. The abyss stirs...",
                            .rows = 6,
                            .cols = 50,
                        });
                        current_state = .main_menu;
                        continue;
                    },
                }

                if (menu_result.choice) |choice| {
                    if (state_module.route_from_menu_choice(choice)) |next_state| {
                        current_state = next_state;
                    } else {
                        try messages.show(.{
                            .text = "The Void does not recognize this path...",
                            .rows = 6,
                            .cols = 50,
                        });
                        current_state = .main_menu;
                    }
                } else {
                    try messages.show(.{
                        .text = "The Void does not recognize this path...",
                        .rows = 6,
                        .cols = 50,
                    });
                    current_state = .main_menu;
                }
            },
            .ui => {
                const ui_result = try ui.run(current_theme);

                if (ui_result.output == c.BSDDIALOG_OK and ui_result.selected_theme != null) {
                    current_theme = ui_result.selected_theme.?;
                    switch (current_theme) {
                        .doom => try theme.apply(),
                        .orangey_black => try theme.apply_orangey_black(),
                        .black_white => try theme.apply_black_white(),
                    }
                    current_state = .ui;
                    continue;
                }

                current_state = .main_menu;
            },
            .the_summoning_ritual => {
                const the_summoning_ritual_result = try the_summoning_ritual.run(selected_output_buffer[0..]);

                if (the_summoning_ritual_result.output == c.BSDDIALOG_OK) {
                    const formatted_message = try dry_run_installer.apply_selection_and_build_summary(
                        std.heap.c_allocator,
                        .the_summoning_ritual,
                        the_summoning_ritual_result.selected,
                    );
                    defer std.heap.c_allocator.free(formatted_message);

                    try messages.show(.{ .text = formatted_message, .rows = 20, .cols = 96 });
                } else {
                    try messages.show(.{
                        .text = "You fled the chamber. No changes made to your fate.",
                        .rows = 6,
                        .cols = 60,
                    });
                }

                current_state = .main_menu;
            },
            .extras => {
                const extras_result = try extras.run(selected_output_buffer[0..]);

                if (extras_result.output == c.BSDDIALOG_OK) {
                    const formatted_message = try dry_run_installer.apply_selection_and_build_summary(
                        std.heap.c_allocator,
                        .extras,
                        extras_result.selected,
                    );
                    defer std.heap.c_allocator.free(formatted_message);

                    try messages.show(.{ .text = formatted_message, .rows = 20, .cols = 96 });
                } else {
                    try messages.show(.{
                        .text = "No extras selected. The void remains untouched.",
                        .rows = 6,
                        .cols = 60,
                    });
                }

                current_state = .main_menu;
            },
            .lore => {
                try lore.run();
                current_state = .main_menu;
            },
            .seek_help => {
                try seek_help.run();
                current_state = .main_menu;
            },
            .health => {
                try health.run();
                current_state = .main_menu;
            },
            .exit => unreachable,
        }
    }
}
