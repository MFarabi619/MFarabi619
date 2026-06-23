const std = @import("std");

// Zephyr headers exposed through the translated `sys` module. Append here
// to surface a new driver/subsystem to Zig code.
const sys_headers = [_][]const u8{
    "zephyr/kernel.h",
    "zephyr/drivers/gpio.h",
    "zephyr/drivers/led_strip.h",
    "zephyr/sys/printk.h",
};

// Pre-translation stub. Picolibc's <sys/_types.h> references typedefs it
// doesn't fully provide under translate-c; Aro also fails on inline asm,
// so we neuter compiler_barrier() — its memory clobber is a compile-time
// fence only, no runtime effect.
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

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const root_path = b.option([]const u8, "root", "absolute path to application root .zig") orelse
        @panic("zephyr-lang-zig: -Droot is required");
    const output_name = b.option([]const u8, "output-name", "basename for emitted .o") orelse "app_zig";
    const ticks_per_sec = b.option(i64, "ticks-per-sec", "Zephyr CONFIG_SYS_CLOCK_TICKS_PER_SEC") orelse
        @panic("zephyr-lang-zig: -Dticks-per-sec is required");
    const sysroot = b.option([]const u8, "sysroot", "Zephyr SDK sysroot directory") orelse
        @panic("zephyr-lang-zig: -Dsysroot is required");
    const dt_path = b.option([]const u8, "dt", "absolute path to generated dt.zig");

    const user_includes_arg = b.option([]const u8, "user-includes", "pipe-separated -I dirs") orelse "";
    const sys_includes_arg = b.option([]const u8, "sys-includes", "pipe-separated -isystem dirs") orelse "";
    const c_defines_arg = b.option([]const u8, "c-defines", "pipe-separated NAME or NAME=value macros") orelse "";

    const wf = b.addWriteFiles();

    const libc_content = b.fmt(
        \\include_dir={s}/include
        \\sys_include_dir={s}/include
        \\crt_dir={s}/lib
        \\msvc_lib_dir=
        \\kernel32_lib_dir=
        \\gcc_dir=
        \\
    , .{ sysroot, sysroot, sysroot });
    const libc_lp = wf.add("zig_libc.txt", libc_content);

    var stub: std.ArrayList(u8) = .empty;
    defer stub.deinit(b.allocator);
    try stub.appendSlice(b.allocator, stub_prelude);
    if (target.result.cpu.arch.isXtensa()) {
        try stub.appendSlice(b.allocator, "#define __IEEE_LITTLE_ENDIAN 1\n");
    }
    try stub.appendSlice(b.allocator, stub_pre_includes);
    for (sys_headers) |h| try stub.print(b.allocator, "#include <{s}>\n", .{h});
    const stub_lp = wf.add("zephyr_stub.h", stub.items);

    const sys_translate = b.addTranslateC(.{
        .root_source_file = stub_lp,
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
    const sys_mod = sys_translate.createModule();

    const timing = b.createModule(.{ .root_source_file = b.path("lib/timing.zig") });
    const ring_buffer = b.createModule(.{ .root_source_file = b.path("lib/ring_buffer.zig") });
    const test_helpers = b.createModule(.{ .root_source_file = b.path("lib/test_helpers.zig") });

    const zephyr = b.createModule(.{ .root_source_file = b.path("lib/zephyr.zig") });
    zephyr.addImport("timing", timing);
    zephyr.addImport("sys", sys_mod);

    const build_config = b.addOptions();
    build_config.addOption(i64, "ticks_per_sec", ticks_per_sec);
    zephyr.addOptions("build_config", build_config);

    const dt_mod: ?*std.Build.Module = if (dt_path) |path| blk: {
        const m = b.createModule(.{ .root_source_file = .{ .cwd_relative = path } });
        m.addImport("sys", sys_mod);
        break :blk m;
    } else null;

    const obj = b.addObject(.{
        .name = output_name,
        .root_module = b.createModule(.{
            .root_source_file = .{ .cwd_relative = root_path },
            .target = target,
            .optimize = optimize,
            .link_libc = true,
            .pic = false,
            .stack_check = false,
        }),
    });
    obj.setLibCFile(libc_lp);
    obj.root_module.addImport("zephyr", zephyr);
    obj.root_module.addImport("timing", timing);
    obj.root_module.addImport("ring_buffer", ring_buffer);
    obj.root_module.addImport("test_helpers", test_helpers);
    obj.root_module.addImport("sys", sys_mod);
    obj.root_module.addOptions("build_config", build_config);
    if (dt_mod) |dt| obj.root_module.addImport("dt", dt);

    b.getInstallStep().dependOn(&b.addInstallArtifact(obj, .{
        .dest_dir = .{ .override = .{ .custom = "obj" } },
    }).step);
}
