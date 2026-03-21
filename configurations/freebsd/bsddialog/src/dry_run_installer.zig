const std = @import("std");

const OwnedStringList = std.array_list.Managed([]u8);
const BorrowedStringList = std.array_list.Managed([]const u8);

pub const Category = enum {
    the_summoning_ritual,
    extras,
};

const config_file_path = "doombsd.conf";
const legacy_summoning_config_key = "doombsd_the_summoning_ritual";
const legacy_extras_config_key = "doombsd_extras";
const summoning_enable_prefix = "doombsd_summoning_";
const extras_enable_prefix = "doombsd_extras_";
const enable_suffix = "_enable";

const ConfigState = struct {
    the_summoning_ritual_ids: OwnedStringList,
    extras_ids: OwnedStringList,

    fn init(allocator: std.mem.Allocator) ConfigState {
        return .{
            .the_summoning_ritual_ids = OwnedStringList.init(allocator),
            .extras_ids = OwnedStringList.init(allocator),
        };
    }

    fn deinit(config_state: *ConfigState, allocator: std.mem.Allocator) void {
        free_list_items(allocator, &config_state.the_summoning_ritual_ids);
        free_list_items(allocator, &config_state.extras_ids);
        config_state.the_summoning_ritual_ids.deinit();
        config_state.extras_ids.deinit();
    }
};

pub fn apply_selection_and_build_summary(
    allocator: std.mem.Allocator,
    category: Category,
    serialized_selection: []const u8,
) ![:0]u8 {
    var desired_ids = OwnedStringList.init(allocator);
    defer {
        free_list_items(allocator, &desired_ids);
        desired_ids.deinit();
    }

    try parse_selection_to_ids(allocator, category, serialized_selection, &desired_ids);

    var config_state = try load_config_state(allocator);
    defer config_state.deinit(allocator);

    const previous_ids = switch (category) {
        .the_summoning_ritual => &config_state.the_summoning_ritual_ids,
        .extras => &config_state.extras_ids,
    };

    var install_ids = BorrowedStringList.init(allocator);
    defer install_ids.deinit();

    var uninstall_ids = BorrowedStringList.init(allocator);
    defer uninstall_ids.deinit();

    for (desired_ids.items) |desired_id| {
        if (!contains_string(previous_ids.items, desired_id)) {
            try install_ids.append(desired_id);
        }
    }

    for (previous_ids.items) |previous_id| {
        if (!contains_string(desired_ids.items, previous_id)) {
            try uninstall_ids.append(previous_id);
        }
    }

    replace_owned_list(allocator, previous_ids, desired_ids.items) catch |error_value| {
        return error_value;
    };

    try write_config_state(allocator, &config_state);

    return try build_summary_message(allocator, category, install_ids.items, uninstall_ids.items);
}

pub fn is_item_selected_by_default(
    allocator: std.mem.Allocator,
    category: Category,
    package_name: [*:0]const u8,
    probe_commands: []const []const u8,
) !bool {
    const package_id = try map_package_name_to_id(allocator, category, std.mem.span(package_name));
    defer allocator.free(package_id);

    var config_state = try load_config_state(allocator);
    defer config_state.deinit(allocator);

    const selected_ids = switch (category) {
        .the_summoning_ritual => config_state.the_summoning_ritual_ids.items,
        .extras => config_state.extras_ids.items,
    };

    if (contains_string(selected_ids, package_id)) {
        return true;
    }

    for (probe_commands) |probe_command| {
        if (command_exists_in_path(probe_command)) {
            return true;
        }
    }

    return false;
}

fn parse_selection_to_ids(
    allocator: std.mem.Allocator,
    category: Category,
    serialized_selection: []const u8,
    output_ids: *OwnedStringList,
) !void {
    var index: usize = 0;
    while (index < serialized_selection.len) {
        while (index < serialized_selection.len and serialized_selection[index] == ' ') : (index += 1) {}
        if (index >= serialized_selection.len) break;

        var token_start = index;
        var token_end = index;

        if (serialized_selection[index] == '"') {
            token_start = index + 1;
            index += 1;
            while (index < serialized_selection.len and serialized_selection[index] != '"') : (index += 1) {}
            token_end = index;
            if (index < serialized_selection.len) index += 1;
        } else {
            while (index < serialized_selection.len and serialized_selection[index] != ' ') : (index += 1) {}
            token_end = index;
        }

        if (token_end <= token_start) continue;

        const raw_package_name = serialized_selection[token_start..token_end];
        const package_id = try map_package_name_to_id(allocator, category, raw_package_name);
        errdefer allocator.free(package_id);

        if (!contains_string(output_ids.items, package_id)) {
            try output_ids.append(package_id);
        } else {
            allocator.free(package_id);
        }
    }
}

pub fn map_package_name_to_id(
    allocator: std.mem.Allocator,
    category: Category,
    package_name: []const u8,
) ![]u8 {
    const normalized_name = try normalize_id_part(allocator, package_name);
    defer allocator.free(normalized_name);

    if (lookup_curated_id(normalized_name)) |curated_id| {
        return allocator.dupe(u8, curated_id);
    }

    const prefix = switch (category) {
        .the_summoning_ritual => "doombsd.the_summoning_ritual",
        .extras => "doombsd.extras",
    };

    return std.fmt.allocPrint(allocator, "{s}.{s}", .{ prefix, normalized_name });
}

fn lookup_curated_id(normalized_package_name: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, normalized_package_name, "emacs")) return "doombsd.editor.emacs";
    if (std.mem.eql(u8, normalized_package_name, "neovim")) return "doombsd.editor.neovimd";

    if (std.mem.eql(u8, normalized_package_name, "kitty")) return "doombsd.term.kitty";

    if (std.mem.eql(u8, normalized_package_name, "jetbrains_mono")) return "doombsd.fonts.jetbrains-mono";
    if (std.mem.eql(u8, normalized_package_name, "nerd_fonts")) return "doombsd.fonts.nerd-fonts";
    if (std.mem.eql(u8, normalized_package_name, "noto_emoji")) return "doombsd.fonts.noto-emoji";

    if (std.mem.eql(u8, normalized_package_name, "fastfetch")) return "doombsd.tools.fastfetch";
    if (std.mem.eql(u8, normalized_package_name, "direnv")) return "doombsd.tools.direnv";
    if (std.mem.eql(u8, normalized_package_name, "arduino")) return "doombsd.tools.arduino";
    if (std.mem.eql(u8, normalized_package_name, "television")) return "doombsd.tools.television";
    if (std.mem.eql(u8, normalized_package_name, "btop")) return "doombsd.tools.btop";
    if (std.mem.eql(u8, normalized_package_name, "lazygit")) return "doombsd.tools.lazygit";
    if (std.mem.eql(u8, normalized_package_name, "zellij")) return "doombsd.tools.zellij";

    if (std.mem.eql(u8, normalized_package_name, "docker")) return "doombsd.virtualisation.docker";
    if (std.mem.eql(u8, normalized_package_name, "docker_compose")) return "doombsd.virtualisation.docker_compose";
    if (std.mem.eql(u8, normalized_package_name, "podman")) return "doombsd.virtualisation.podman";
    if (std.mem.eql(u8, normalized_package_name, "kubernetes")) return "doombsd.virtualisation.kubernetes";
    if (std.mem.eql(u8, normalized_package_name, "k9s")) return "doombsd.virtualisation.kubernetes";
    if (std.mem.eql(u8, normalized_package_name, "framework_system")) return "doombsd.hardware.framework-system";
    if (std.mem.eql(u8, normalized_package_name, "framework_tool")) return "doombsd.hardware.framework-tool";
    if (std.mem.eql(u8, normalized_package_name, "framework_tool_tui")) return "doombsd.hardware.framework-tool-tui";

    if (std.mem.eql(u8, normalized_package_name, "tailscale")) return "doombsd.networking.tailscale";
    if (std.mem.eql(u8, normalized_package_name, "caddy")) return "doombsd.networking.caddy";
    if (std.mem.eql(u8, normalized_package_name, "bmon")) return "doombsd.networking.bmon";
    if (std.mem.eql(u8, normalized_package_name, "lazyssh")) return "doombsd.networking.lazyssh";
    if (std.mem.eql(u8, normalized_package_name, "socat")) return "doombsd.networking.socat";
    if (std.mem.eql(u8, normalized_package_name, "websocat")) return "doombsd.networking.websocat";

    if (std.mem.eql(u8, normalized_package_name, "rust")) return "doombsd.languages.rust";
    if (std.mem.eql(u8, normalized_package_name, "c")) return "doombsd.languages.c";
    if (std.mem.eql(u8, normalized_package_name, "zig")) return "doombsd.languages.zig";
    if (std.mem.eql(u8, normalized_package_name, "python")) return "doombsd.languages.python";
    if (std.mem.eql(u8, normalized_package_name, "ruby")) return "doombsd.languages.ruby";
    if (std.mem.eql(u8, normalized_package_name, "go")) return "doombsd.languages.go";

    if (std.mem.eql(u8, normalized_package_name, "openssh")) return "doombsd.services.openssh";
    if (std.mem.eql(u8, normalized_package_name, "fail2ban")) return "doombsd.security.fail2ban";

    return null;
}

fn command_exists_in_path(command_name: []const u8) bool {
    const path_value = std.posix.getenv("PATH") orelse return false;
    var path_iterator = std.mem.splitScalar(u8, path_value, ':');

    while (path_iterator.next()) |path_entry| {
        if (path_entry.len == 0) continue;

        var full_path_buffer: [std.fs.max_path_bytes]u8 = undefined;
        const candidate_path = std.fmt.bufPrint(&full_path_buffer, "{s}/{s}", .{ path_entry, command_name }) catch continue;
        if (std.fs.cwd().access(candidate_path, .{})) |_| {
            return true;
        } else |_| {}
    }

    return false;
}

fn normalize_id_part(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    var normalized_builder = std.array_list.Managed(u8).init(allocator);
    defer normalized_builder.deinit();

    var previous_was_separator = false;
    for (value) |character| {
        const lower_character = std.ascii.toLower(character);
        if (std.ascii.isAlphanumeric(lower_character)) {
            try normalized_builder.append(lower_character);
            previous_was_separator = false;
            continue;
        }

        if (!previous_was_separator) {
            try normalized_builder.append('_');
            previous_was_separator = true;
        }
    }

    while (normalized_builder.items.len > 0 and normalized_builder.items[normalized_builder.items.len - 1] == '_') {
        _ = normalized_builder.pop();
    }

    if (normalized_builder.items.len == 0) {
        try normalized_builder.appendSlice("unknown");
    }

    return normalized_builder.toOwnedSlice();
}

fn load_config_state(allocator: std.mem.Allocator) !ConfigState {
    var config_state = ConfigState.init(allocator);
    errdefer config_state.deinit(allocator);

    const file_contents = std.fs.cwd().readFileAlloc(allocator, config_file_path, 1024 * 1024) catch |error_value| {
        if (error_value == error.FileNotFound) {
            return config_state;
        }
        return error_value;
    };
    defer allocator.free(file_contents);

    if (extract_value_for_key(file_contents, legacy_summoning_config_key)) |value| {
        try parse_id_list_to_owned_list(allocator, value, &config_state.the_summoning_ritual_ids);
    } else if (extract_value_for_key(file_contents, "doombsd.the_summoning_ritual")) |legacy_value| {
        try parse_id_list_to_owned_list(allocator, legacy_value, &config_state.the_summoning_ritual_ids);
    }

    if (extract_value_for_key(file_contents, legacy_extras_config_key)) |value| {
        try parse_id_list_to_owned_list(allocator, value, &config_state.extras_ids);
    } else if (extract_value_for_key(file_contents, "doombsd.extras")) |legacy_value| {
        try parse_id_list_to_owned_list(allocator, legacy_value, &config_state.extras_ids);
    }

    try parse_enable_lines_to_owned_list(allocator, file_contents, .the_summoning_ritual, summoning_enable_prefix, &config_state.the_summoning_ritual_ids);
    try parse_enable_lines_to_owned_list(allocator, file_contents, .extras, extras_enable_prefix, &config_state.extras_ids);

    return config_state;
}

fn parse_enable_lines_to_owned_list(
    allocator: std.mem.Allocator,
    file_contents: []const u8,
    category: Category,
    key_prefix: []const u8,
    output_list: *OwnedStringList,
) !void {
    var parsed_list = OwnedStringList.init(allocator);
    defer {
        if (parsed_list.items.len == 0) {
            parsed_list.deinit();
        }
    }

    var line_iterator = std.mem.splitScalar(u8, file_contents, '\n');
    while (line_iterator.next()) |line| {
        const trimmed_line = std.mem.trim(u8, line, " \t\r");
        if (trimmed_line.len == 0 or trimmed_line[0] == '#') continue;

        const equals_index = std.mem.indexOfScalar(u8, trimmed_line, '=') orelse continue;
        const key = std.mem.trim(u8, trimmed_line[0..equals_index], " \t");
        const value = trim_optional_double_quotes(std.mem.trim(u8, trimmed_line[equals_index + 1 ..], " \t\r"));

        if (!std.mem.startsWith(u8, key, key_prefix)) continue;
        if (!std.mem.endsWith(u8, key, enable_suffix)) continue;
        if (!is_enabled_value(value)) continue;

        const key_tail = key[key_prefix.len .. key.len - enable_suffix.len];
        const package_id = try package_id_from_rc_key(allocator, category, key_tail);
        errdefer allocator.free(package_id);

        if (!contains_string(parsed_list.items, package_id)) {
            try parsed_list.append(package_id);
        } else {
            allocator.free(package_id);
        }
    }

    if (parsed_list.items.len == 0) return;

    free_list_items(allocator, output_list);
    output_list.deinit();
    output_list.* = parsed_list;
}

fn package_id_from_rc_key(allocator: std.mem.Allocator, category: Category, key_tail: []const u8) ![]u8 {
    if (lookup_curated_id_from_rc_key(key_tail)) |curated_id| {
        return allocator.dupe(u8, curated_id);
    }

    return switch (category) {
        .the_summoning_ritual => std.fmt.allocPrint(allocator, "doombsd.the_summoning_ritual.{s}", .{key_tail}),
        .extras => std.fmt.allocPrint(allocator, "doombsd.extras.{s}", .{key_tail}),
    };
}

fn lookup_curated_id_from_rc_key(key_tail: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, key_tail, "editor_emacs")) return "doombsd.editor.emacs";
    if (std.mem.eql(u8, key_tail, "editor_neovimd")) return "doombsd.editor.neovimd";

    if (std.mem.eql(u8, key_tail, "term_kitty")) return "doombsd.term.kitty";

    if (std.mem.eql(u8, key_tail, "fonts_jetbrains_mono")) return "doombsd.fonts.jetbrains-mono";
    if (std.mem.eql(u8, key_tail, "fonts_nerd_fonts")) return "doombsd.fonts.nerd-fonts";
    if (std.mem.eql(u8, key_tail, "fonts_noto_emoji")) return "doombsd.fonts.noto-emoji";

    if (std.mem.eql(u8, key_tail, "tools_fastfetch")) return "doombsd.tools.fastfetch";
    if (std.mem.eql(u8, key_tail, "tools_direnv")) return "doombsd.tools.direnv";
    if (std.mem.eql(u8, key_tail, "tools_arduino")) return "doombsd.tools.arduino";
    if (std.mem.eql(u8, key_tail, "tools_television")) return "doombsd.tools.television";
    if (std.mem.eql(u8, key_tail, "tools_btop")) return "doombsd.tools.btop";
    if (std.mem.eql(u8, key_tail, "tools_lazygit")) return "doombsd.tools.lazygit";
    if (std.mem.eql(u8, key_tail, "tools_zellij")) return "doombsd.tools.zellij";

    if (std.mem.eql(u8, key_tail, "virtualisation_docker")) return "doombsd.virtualisation.docker";
    if (std.mem.eql(u8, key_tail, "virtualisation_docker_compose")) return "doombsd.virtualisation.docker_compose";
    if (std.mem.eql(u8, key_tail, "virtualisation_podman")) return "doombsd.virtualisation.podman";
    if (std.mem.eql(u8, key_tail, "virtualisation_kubernetes")) return "doombsd.virtualisation.kubernetes";

    if (std.mem.eql(u8, key_tail, "hardware_framework_system")) return "doombsd.hardware.framework-system";
    if (std.mem.eql(u8, key_tail, "hardware_framework_tool")) return "doombsd.hardware.framework-tool";
    if (std.mem.eql(u8, key_tail, "hardware_framework_tool_tui")) return "doombsd.hardware.framework-tool-tui";

    if (std.mem.eql(u8, key_tail, "networking_tailscale")) return "doombsd.networking.tailscale";
    if (std.mem.eql(u8, key_tail, "networking_caddy")) return "doombsd.networking.caddy";
    if (std.mem.eql(u8, key_tail, "networking_bmon")) return "doombsd.networking.bmon";
    if (std.mem.eql(u8, key_tail, "networking_lazyssh")) return "doombsd.networking.lazyssh";
    if (std.mem.eql(u8, key_tail, "networking_socat")) return "doombsd.networking.socat";
    if (std.mem.eql(u8, key_tail, "networking_websocat")) return "doombsd.networking.websocat";

    if (std.mem.eql(u8, key_tail, "languages_rust")) return "doombsd.languages.rust";
    if (std.mem.eql(u8, key_tail, "languages_c")) return "doombsd.languages.c";
    if (std.mem.eql(u8, key_tail, "languages_zig")) return "doombsd.languages.zig";
    if (std.mem.eql(u8, key_tail, "languages_python")) return "doombsd.languages.python";
    if (std.mem.eql(u8, key_tail, "languages_ruby")) return "doombsd.languages.ruby";
    if (std.mem.eql(u8, key_tail, "languages_go")) return "doombsd.languages.go";

    if (std.mem.eql(u8, key_tail, "services_openssh")) return "doombsd.services.openssh";
    if (std.mem.eql(u8, key_tail, "security_fail2ban")) return "doombsd.security.fail2ban";

    return null;
}

fn is_enabled_value(value: []const u8) bool {
    return std.ascii.eqlIgnoreCase(value, "YES") or
        std.ascii.eqlIgnoreCase(value, "TRUE") or
        std.ascii.eqlIgnoreCase(value, "ON") or
        std.mem.eql(u8, value, "1");
}

fn extract_value_for_key(file_contents: []const u8, key: []const u8) ?[]const u8 {
    var key_pattern_buffer: [128]u8 = undefined;
    const key_pattern = std.fmt.bufPrint(&key_pattern_buffer, "{s}=", .{key}) catch return null;

    const key_index = std.mem.indexOf(u8, file_contents, key_pattern) orelse return null;
    var value_start = key_index + key_pattern.len;

    while (value_start < file_contents.len and (file_contents[value_start] == ' ' or file_contents[value_start] == '\t')) {
        value_start += 1;
    }

    if (value_start >= file_contents.len) return null;

    if (file_contents[value_start] == '"') {
        value_start += 1;
        const tail = file_contents[value_start..];
        const end_rel = std.mem.indexOfScalar(u8, tail, '"') orelse return null;
        return tail[0..end_rel];
    }

    const line_tail = file_contents[value_start..];
    const newline_rel = std.mem.indexOfScalar(u8, line_tail, '\n') orelse line_tail.len;
    return trim_optional_double_quotes(std.mem.trim(u8, line_tail[0..newline_rel], " \t\r"));
}

fn parse_id_list_to_owned_list(
    allocator: std.mem.Allocator,
    serialized_ids: []const u8,
    output_list: *OwnedStringList,
) !void {
    free_list_items(allocator, output_list);
    output_list.clearRetainingCapacity();

    var token_iterator = std.mem.tokenizeAny(u8, serialized_ids, ", \t\r");
    while (token_iterator.next()) |token| {
        const owned_token = try allocator.dupe(u8, token);
        try output_list.append(owned_token);
    }
}

fn replace_owned_list(
    allocator: std.mem.Allocator,
    destination: *OwnedStringList,
    source_items: []const []u8,
) !void {
    free_list_items(allocator, destination);
    destination.clearRetainingCapacity();

    for (source_items) |item| {
        const copied_item = try allocator.dupe(u8, item);
        try destination.append(copied_item);
    }
}

fn write_config_state(allocator: std.mem.Allocator, config_state: *const ConfigState) !void {
    var output = std.array_list.Managed(u8).init(allocator);
    defer output.deinit();

    const writer = output.writer();
    try writer.writeAll("# DoomBSD dry-run configuration\n\n");

    for (config_state.the_summoning_ritual_ids.items) |package_id| {
        const enable_key = try make_enable_key_for_id(allocator, .the_summoning_ritual, package_id);
        defer allocator.free(enable_key);
        try writer.print("{s}=\"YES\"\n", .{enable_key});
    }

    if (config_state.the_summoning_ritual_ids.items.len > 0 and config_state.extras_ids.items.len > 0) {
        try writer.writeByte('\n');
    }

    for (config_state.extras_ids.items) |package_id| {
        const enable_key = try make_enable_key_for_id(allocator, .extras, package_id);
        defer allocator.free(enable_key);
        try writer.print("{s}=\"YES\"\n", .{enable_key});
    }

    try std.fs.cwd().writeFile(.{ .sub_path = config_file_path, .data = output.items });
}

fn make_enable_key_for_id(
    allocator: std.mem.Allocator,
    category: Category,
    package_id: []const u8,
) ![]u8 {
    const id_tail = if (std.mem.startsWith(u8, package_id, "doombsd.")) package_id[8..] else package_id;
    const readable_tail = try readable_key_tail_from_id(allocator, id_tail);
    defer allocator.free(readable_tail);

    const key_prefix = switch (category) {
        .the_summoning_ritual => summoning_enable_prefix,
        .extras => extras_enable_prefix,
    };

    return std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ key_prefix, readable_tail, enable_suffix });
}

fn readable_key_tail_from_id(allocator: std.mem.Allocator, id_tail: []const u8) ![]u8 {
    var normalized = std.array_list.Managed(u8).init(allocator);
    defer normalized.deinit();

    for (id_tail) |character| {
        switch (character) {
            '.', '-' => try normalized.append('_'),
            else => try normalized.append(character),
        }
    }

    return normalized.toOwnedSlice();
}

fn trim_optional_double_quotes(value: []const u8) []const u8 {
    if (value.len >= 2 and value[0] == '"' and value[value.len - 1] == '"') {
        return value[1 .. value.len - 1];
    }
    return value;
}

fn build_summary_message(
    allocator: std.mem.Allocator,
    category: Category,
    install_ids: []const []const u8,
    uninstall_ids: []const []const u8,
) ![:0]u8 {
    var output = std.array_list.Managed(u8).init(allocator);
    defer output.deinit();

    const writer = output.writer();
    try writer.writeAll("DRY RUN PACKAGE PLAN\n\n");
    switch (category) {
        .the_summoning_ritual => try writer.writeAll("Profile: The Summoning Ritual\n"),
        .extras => try writer.writeAll("Profile: Extras\n"),
    }
    try writer.writeAll("\nInstall:\n");
    if (install_ids.len == 0) {
        try writer.writeAll("  - (none)\n");
    } else {
        for (install_ids) |install_id| {
            try writer.print("  + {s}\n", .{install_id});
        }
    }

    try writer.writeAll("\nUninstall:\n");
    if (uninstall_ids.len == 0) {
        try writer.writeAll("  - (none)\n");
    } else {
        for (uninstall_ids) |uninstall_id| {
            try writer.print("  - {s}\n", .{uninstall_id});
        }
    }

    try writer.writeAll("\nDry-run commands:\n");
    if (install_ids.len == 0 and uninstall_ids.len == 0) {
        try writer.writeAll("  (none)\n");
    } else {
        for (install_ids) |install_id| {
            try writer.print("  pkg install -y {s}    # dry run\n", .{install_id});
        }
        for (uninstall_ids) |uninstall_id| {
            try writer.print("  pkg delete -y {s}    # dry run\n", .{uninstall_id});
        }
    }

    try writer.writeAll("\nNo package changes were executed.\n");
    return allocator.dupeZ(u8, output.items);
}

fn contains_string(items: []const []const u8, needle: []const u8) bool {
    for (items) |item| {
        if (std.mem.eql(u8, item, needle)) {
            return true;
        }
    }
    return false;
}

fn free_list_items(allocator: std.mem.Allocator, list: *OwnedStringList) void {
    for (list.items) |item| {
        allocator.free(item);
    }
}

test "map editor ids to requested values" {
    const allocator = std.testing.allocator;

    const emacs_id = try map_package_name_to_id(allocator, .the_summoning_ritual, "emacs");
    defer allocator.free(emacs_id);
    try std.testing.expect(std.mem.eql(u8, emacs_id, "doombsd.editor.emacs"));

    const neovim_id = try map_package_name_to_id(allocator, .the_summoning_ritual, "neovim");
    defer allocator.free(neovim_id);
    try std.testing.expect(std.mem.eql(u8, neovim_id, "doombsd.editor.neovimd"));
}

test "map requested domain ids" {
    const allocator = std.testing.allocator;

    const fastfetch_id = try map_package_name_to_id(allocator, .extras, "fastfetch");
    defer allocator.free(fastfetch_id);
    try std.testing.expect(std.mem.eql(u8, fastfetch_id, "doombsd.tools.fastfetch"));

    const docker_id = try map_package_name_to_id(allocator, .extras, "docker");
    defer allocator.free(docker_id);
    try std.testing.expect(std.mem.eql(u8, docker_id, "doombsd.virtualisation.docker"));

    const tailscale_id = try map_package_name_to_id(allocator, .extras, "tailscale");
    defer allocator.free(tailscale_id);
    try std.testing.expect(std.mem.eql(u8, tailscale_id, "doombsd.networking.tailscale"));

    const lazyssh_id = try map_package_name_to_id(allocator, .extras, "lazyssh");
    defer allocator.free(lazyssh_id);
    try std.testing.expect(std.mem.eql(u8, lazyssh_id, "doombsd.networking.lazyssh"));

    const socat_id = try map_package_name_to_id(allocator, .extras, "socat");
    defer allocator.free(socat_id);
    try std.testing.expect(std.mem.eql(u8, socat_id, "doombsd.networking.socat"));

    const websocat_id = try map_package_name_to_id(allocator, .extras, "websocat");
    defer allocator.free(websocat_id);
    try std.testing.expect(std.mem.eql(u8, websocat_id, "doombsd.networking.websocat"));

    const zig_id = try map_package_name_to_id(allocator, .extras, "zig");
    defer allocator.free(zig_id);
    try std.testing.expect(std.mem.eql(u8, zig_id, "doombsd.languages.zig"));
}

test "normalize id part lowers and sanitizes" {
    const allocator = std.testing.allocator;
    const normalized = try normalize_id_part(allocator, "Hyprland (HyDE)");
    defer allocator.free(normalized);

    try std.testing.expect(std.mem.eql(u8, normalized, "hyprland_hyde"));
}
