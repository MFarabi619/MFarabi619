const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const doombsd_mod = b.addModule("doombsd", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    doombsd_mod.addIncludePath(b.path("lib"));
    doombsd_mod.link_libc = true;

    const exe_root = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "doombsd", .module = doombsd_mod },
        },
    });
    exe_root.addIncludePath(b.path("lib"));
    exe_root.link_libc = true;

    const exe = b.addExecutable(.{
        .name = "doombsd-installer",
        .root_module = exe_root,
    });

    exe.addLibraryPath(b.path("lib"));
    exe.linkSystemLibrary("bsddialog");

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the DoomBSD installer demo");
    run_step.dependOn(&run_cmd.step);

    const mod_tests = b.addTest(.{
        .root_module = doombsd_mod,
    });
    mod_tests.addLibraryPath(b.path("lib"));
    mod_tests.linkSystemLibrary("bsddialog");

    const run_mod_tests = b.addRunArtifact(mod_tests);
    run_mod_tests.skip_foreign_checks = true;

    const test_step = b.step("test", "Run Zig unit tests");
    test_step.dependOn(&run_mod_tests.step);
}
