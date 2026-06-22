const std = @import("std");

const ModuleSpec = struct {
    name: []const u8,
    file: []const u8,
    deps: []const []const u8 = &.{},
};

const lib_specs = [_]ModuleSpec{
    .{ .name = "timing", .file = "lib/timing.zig" },
    .{ .name = "ring_buffer", .file = "lib/ring_buffer.zig" },
    .{ .name = "test_helpers", .file = "lib/test_helpers.zig" },
    .{ .name = "zephyr", .file = "lib/zephyr.zig", .deps = &.{ "timing", "build_config", "sys" } },
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const root_path = b.option([]const u8, "root", "absolute path to application root .zig") orelse
        @panic("zephyr-lang-zig: -Droot is required");
    const output_name = b.option([]const u8, "output-name", "basename for emitted .o") orelse "app_zig";
    const ticks_per_sec = b.option(i64, "ticks-per-sec", "Zephyr CONFIG_SYS_CLOCK_TICKS_PER_SEC") orelse
        @panic("zephyr-lang-zig: -Dticks-per-sec is required");
    const libc_path = b.option([]const u8, "libc", "absolute path to libc.txt");
    const dt_path = b.option([]const u8, "dt", "absolute path to generated dt.zig");

    const user_includes_arg = b.option([]const u8, "user-includes", "pipe-separated -I dirs") orelse "";
    const sys_includes_arg = b.option([]const u8, "sys-includes", "pipe-separated -isystem dirs") orelse "";
    const c_defines_arg = b.option([]const u8, "c-defines", "pipe-separated NAME or NAME=value macros") orelse "";

    const sys_translate = b.addTranslateC(.{
        .root_source_file = b.path("scripts/zephyr_stub.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    // Some Zephyr include paths appear in BOTH the user (-I) and system (-isystem)
    // lists. Aro rejects duplicate paths across these lists, so we add system
    // paths first and skip user paths that overlap.
    var sys_seen = std.StringHashMap(void).init(b.allocator);
    defer sys_seen.deinit();
    {
        var iter = std.mem.tokenizeScalar(u8, sys_includes_arg, '|');
        while (iter.next()) |path| {
            try sys_seen.put(b.dupe(path), {});
            sys_translate.addSystemIncludePath(.{ .cwd_relative = path });
        }
    }
    {
        var iter = std.mem.tokenizeScalar(u8, user_includes_arg, '|');
        while (iter.next()) |path| {
            if (sys_seen.contains(path)) continue;
            sys_translate.addIncludePath(.{ .cwd_relative = path });
        }
    }
    {
        var iter = std.mem.tokenizeScalar(u8, c_defines_arg, '|');
        while (iter.next()) |def| {
            if (std.mem.indexOfScalar(u8, def, '=')) |eq| {
                sys_translate.defineCMacro(def[0..eq], def[eq + 1 ..]);
            } else {
                sys_translate.defineCMacro(def, null);
            }
        }
    }

    const sys_module = sys_translate.createModule();

    var module_map = std.StringHashMap(*std.Build.Module).init(b.allocator);
    defer module_map.deinit();

    const build_config_options = b.addOptions();
    build_config_options.addOption(i64, "ticks_per_sec", ticks_per_sec);
    try module_map.put("build_config", build_config_options.createModule());
    try module_map.put("sys", sys_module);

    if (dt_path) |path| {
        const dt_mod = b.createModule(.{
            .root_source_file = .{ .cwd_relative = path },
        });
        try module_map.put("dt", dt_mod);
    }

    inline for (lib_specs) |spec| {
        var imports: std.ArrayList(std.Build.Module.Import) = .empty;
        defer imports.deinit(b.allocator);
        inline for (spec.deps) |dep_name| {
            const dep_mod = module_map.get(dep_name) orelse
                @panic("zephyr-lang-zig: dep '" ++ dep_name ++ "' missing for module '" ++ spec.name ++ "'");
            try imports.append(b.allocator, .{ .name = dep_name, .module = dep_mod });
        }
        const mod = b.createModule(.{
            .root_source_file = b.path(spec.file),
            .imports = imports.items,
        });
        try module_map.put(spec.name, mod);
    }

    var root_imports: std.ArrayList(std.Build.Module.Import) = .empty;
    defer root_imports.deinit(b.allocator);
    var iter = module_map.iterator();
    while (iter.next()) |entry| {
        try root_imports.append(b.allocator, .{ .name = entry.key_ptr.*, .module = entry.value_ptr.* });
    }

    const obj = b.addObject(.{
        .name = output_name,
        .root_module = b.createModule(.{
            .root_source_file = .{ .cwd_relative = root_path },
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .imports = root_imports.items,
            .pic = false,
            .stack_check = false,
        }),
    });
    if (libc_path) |path| {
        obj.setLibCFile(.{ .cwd_relative = path });
    }

    b.getInstallStep().dependOn(&b.addInstallArtifact(obj, .{
        .dest_dir = .{ .override = .{ .custom = "obj" } },
    }).step);
}
