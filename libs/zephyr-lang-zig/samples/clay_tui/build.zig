const std = @import("std");
const zephyr_lang_zig = @import("zephyr_lang_zig");

pub fn build(builder: *std.Build) !void {
    const target = builder.standardTargetOptions(.{});
    const optimize = builder.standardOptimizeOption(.{});

    const zephyr_lang_zig_dep = builder.dependency("zephyr_lang_zig", .{});
    const app = try zephyr_lang_zig.addApp(builder, zephyr_lang_zig_dep.builder, .{
        .target = target,
        .optimize = optimize,
    });

    const zclay = builder.dependency("zclay", .{ .target = target, .optimize = optimize });
    app.root_module.addImport("zclay", zclay.module("zclay"));

    // Compile clay.c here so its symbols land in this .o (no separate archive).
    const write_files = builder.addWriteFiles();
    const clay_c = write_files.add("clay.c", "#define CLAY_IMPLEMENTATION\n#include <clay.h>\n");
    app.root_module.addCSourceFile(.{ .file = clay_c, .flags = &.{"-ffreestanding"} });
    app.root_module.addIncludePath(zclay.builder.dependency("clay", .{}).path(""));
}
