const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const nuttx_include = b.option([]const u8, "nuttx-include", "NuttX include directory") orelse
        @panic("nuttx-zig: -Dnuttx-include is required");

    const zigzag = b.dependency("zigzag", .{ .target = target, .optimize = optimize });

    const object = b.addObject(.{
        .name = "nuttx_zig",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .pic = false,
        }),
    });
    object.bundle_compiler_rt = !target.result.cpu.arch.isXtensa();
    object.root_module.addIncludePath(.{ .cwd_relative = nuttx_include });
    object.root_module.addImport("zigzag", zigzag.module("zigzag"));

    b.getInstallStep().dependOn(&b.addInstallArtifact(object, .{
        .dest_dir = .{ .override = .{ .custom = "obj" } },
    }).step);
}
