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

    const zigzag = builder.dependency("zigzag", .{ .target = target, .optimize = optimize });
    app.root_module.addImport("zigzag", zigzag.module("zigzag"));
}
