const std = @import("std");
const builtin = @import("builtin");
const zephyr = @import("zephyr");

export fn main() c_int {
    zephyr.say(comptime std.fmt.comptimePrint("Hello World! {s}\n", .{@tagName(builtin.cpu.arch)}));
    return 0;
}
