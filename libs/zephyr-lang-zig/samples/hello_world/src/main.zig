const builtin = @import("builtin");
const zephyr = @import("zephyr");

export fn main() c_int {
    zephyr.print("Hello World! {s}\n", .{@tagName(builtin.cpu.arch)});
    return 0;
}
