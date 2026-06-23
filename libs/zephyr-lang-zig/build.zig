const std = @import("std");

const sys_headers = [_][]const u8{
    "zephyr/kernel.h",
    "zephyr/drivers/gpio.h",
    "zephyr/drivers/eeprom.h",
    "zephyr/drivers/rtc.h",
    "zephyr/drivers/led_strip.h",
    "zephyr/sys/printk.h",
};

// Stubs Picolibc typedefs and Aro-hostile inline asm so translate-c succeeds.
const stub_prelude =
    \\typedef unsigned int wint_t;
    \\typedef int wctype_t;
    \\typedef unsigned int wctrans_t;
    \\#define __machine_mbstate_t_defined
    \\typedef struct {
    \\    int __count;
    \\    union {
    \\        unsigned int __wch;
    \\        unsigned char __wchb[4];
    \\    } __value;
    \\} _mbstate_t;
    \\
;

const stub_pre_includes =
    \\#include <autoconf.h>
    \\#include <zephyr/toolchain/zephyr_stdint.h>
    \\#include <stdint.h>
    \\
    \\#define ZEPHYR_INCLUDE_IRQ_MULTILEVEL_H_
    \\typedef uint32_t _z_irq_t;
    \\
    \\#include <zephyr/toolchain.h>
    \\#undef compiler_barrier
    \\#define compiler_barrier() do {} while (0)
    \\
;

pub const AppOptions = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
};

/// `lib_builder` resolves paths under the zephyr-lang-zig tree: sample build.zigs
/// pass `dep.builder`; the lib's own `build()` passes `builder` itself.
pub fn addApp(
    builder: *std.Build,
    lib_builder: *std.Build,
    opts: AppOptions,
) !*std.Build.Step.Compile {
    const root_path = builder.option([]const u8, "root", "absolute path to application root .zig") orelse
        @panic("zephyr-lang-zig: -Droot is required");
    const output_name = builder.option([]const u8, "output-name", "basename for emitted .o") orelse "app_zig";
    const ticks_per_sec = builder.option(i64, "ticks-per-sec", "Zephyr CONFIG_SYS_CLOCK_TICKS_PER_SEC") orelse
        @panic("zephyr-lang-zig: -Dticks-per-sec is required");
    const sysroot = builder.option([]const u8, "sysroot", "Zephyr SDK sysroot directory") orelse
        @panic("zephyr-lang-zig: -Dsysroot is required");
    const dt_path = builder.option([]const u8, "dt", "absolute path to generated dt.zig");
    const user_includes_arg = builder.option([]const u8, "user-includes", "pipe-separated -I dirs") orelse "";
    const sys_includes_arg = builder.option([]const u8, "sys-includes", "pipe-separated -isystem dirs") orelse "";
    const c_defines_arg = builder.option([]const u8, "c-defines", "pipe-separated NAME or NAME=value macros") orelse "";

    const write_files = builder.addWriteFiles();

    const libc_content = builder.fmt(
        \\include_dir={s}/include
        \\sys_include_dir={s}/include
        \\crt_dir={s}/lib
        \\msvc_lib_dir=
        \\kernel32_lib_dir=
        \\gcc_dir=
        \\
    , .{ sysroot, sysroot, sysroot });
    const libc_path = write_files.add("zig_libc.txt", libc_content);

    var stub: std.ArrayList(u8) = .empty;
    defer stub.deinit(builder.allocator);
    try stub.appendSlice(builder.allocator, stub_prelude);
    if (opts.target.result.cpu.arch.isXtensa()) {
        try stub.appendSlice(builder.allocator, "#define __IEEE_LITTLE_ENDIAN 1\n");
    }
    try stub.appendSlice(builder.allocator, stub_pre_includes);
    for (sys_headers) |header| try stub.print(builder.allocator, "#include <{s}>\n", .{header});
    const stub_path = write_files.add("zephyr_stub.h", stub.items);

    const sys_translate = builder.addTranslateC(.{
        .root_source_file = stub_path,
        .target = opts.target,
        .optimize = opts.optimize,
        .link_libc = true,
    });

    // Aro rejects paths in both -I and -isystem; favor -isystem on overlap.
    var sys_seen = std.StringHashMap(void).init(builder.allocator);
    defer sys_seen.deinit();
    {
        var iter = std.mem.tokenizeScalar(u8, sys_includes_arg, '|');
        while (iter.next()) |path| {
            try sys_seen.put(builder.dupe(path), {});
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
        while (iter.next()) |define_str| {
            if (std.mem.indexOfScalar(u8, define_str, '=')) |eq_pos| {
                sys_translate.defineCMacro(define_str[0..eq_pos], define_str[eq_pos + 1 ..]);
            } else {
                sys_translate.defineCMacro(define_str, null);
            }
        }
    }
    const sys_mod = sys_translate.createModule();

    const timing = builder.createModule(.{ .root_source_file = lib_builder.path("lib/timing.zig") });
    const ring_buffer = builder.createModule(.{ .root_source_file = lib_builder.path("lib/ring_buffer.zig") });
    const test_helpers = builder.createModule(.{ .root_source_file = lib_builder.path("lib/test_helpers.zig") });

    const zephyr = builder.createModule(.{ .root_source_file = lib_builder.path("lib/zephyr.zig") });
    zephyr.addImport("timing", timing);
    zephyr.addImport("sys", sys_mod);

    const build_config = builder.addOptions();
    build_config.addOption(i64, "ticks_per_sec", ticks_per_sec);
    zephyr.addOptions("build_config", build_config);

    const dt_mod: ?*std.Build.Module = if (dt_path) |path| blk: {
        const dt_module = builder.createModule(.{ .root_source_file = .{ .cwd_relative = path } });
        dt_module.addImport("sys", sys_mod);
        break :blk dt_module;
    } else null;

    const obj = builder.addObject(.{
        .name = output_name,
        .root_module = builder.createModule(.{
            .root_source_file = .{ .cwd_relative = root_path },
            .target = opts.target,
            .optimize = opts.optimize,
            .link_libc = true,
            .pic = false,
            .stack_check = false,
        }),
    });
    obj.setLibCFile(libc_path);
    obj.root_module.addImport("zephyr", zephyr);
    obj.root_module.addImport("timing", timing);
    obj.root_module.addImport("ring_buffer", ring_buffer);
    obj.root_module.addImport("test_helpers", test_helpers);
    obj.root_module.addImport("sys", sys_mod);
    obj.root_module.addOptions("build_config", build_config);
    if (dt_mod) |dt_module| obj.root_module.addImport("dt", dt_module);

    builder.getInstallStep().dependOn(&builder.addInstallArtifact(obj, .{
        .dest_dir = .{ .override = .{ .custom = "obj" } },
    }).step);

    return obj;
}

pub fn build(builder: *std.Build) !void {
    // Loaded as a path-dep when -Droot is absent; sample's build.zig calls addApp.
    if (!builder.user_input_options.contains("root")) return;
    const target = builder.standardTargetOptions(.{});
    const optimize = builder.standardOptimizeOption(.{});
    _ = try addApp(builder, builder, .{ .target = target, .optimize = optimize });
}
