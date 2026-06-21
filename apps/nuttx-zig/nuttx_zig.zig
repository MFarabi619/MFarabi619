const c = @cImport({
    @cInclude("nuttx/config.h");
    @cInclude("stdio.h");
});

export fn nuttx_zig_main(_: c_int, _: [*][*:0]u8) c_int {
    _ = c.printf("Hello from Zig on NuttX!\n");
    return 0;
}
