const std = @import("std");
const zephyr_lang_zig = @import("zephyr_lang_zig");
const build_crab = @import("build_crab");

const RUST_LIB_FILENAME = "librust_ffi.a";

pub fn build(builder: *std.Build) !void {
    const target = builder.standardTargetOptions(.{});
    const optimize = builder.standardOptimizeOption(.{});

    const zephyr_lang_zig_dep = builder.dependency("zephyr_lang_zig", .{});
    _ = try zephyr_lang_zig.addApp(builder, zephyr_lang_zig_dep.builder, .{
        .target = target,
        .optimize = optimize,
    });

    const crate_artifacts = build_crab.addCargoBuild(
        builder,
        .{
            .manifest_path = builder.path("Cargo.toml"),
            .cargo_args = &.{ "--release", "--quiet", "--lib" },
            .rust_target = .{ .override = .{} },
        },
        .{ .target = target, .optimize = optimize },
    );

    const install_lib = builder.addInstallFileWithDir(
        crate_artifacts.path(builder, RUST_LIB_FILENAME),
        .lib,
        RUST_LIB_FILENAME,
    );
    builder.getInstallStep().dependOn(&install_lib.step);
}
