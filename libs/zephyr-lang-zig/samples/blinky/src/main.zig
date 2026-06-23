const dt = @import("dt");
const zephyr = @import("zephyr");

const led = zephyr.GpioDtSpec.fromDt(dt.aliases.led0.*.gpios);

pub const panic = zephyr.panic;

pub fn main() !void {
    if (!led.isReady()) return error.LedNotReady;
    try led.configure(zephyr.GPIO_OUTPUT_INACTIVE);

    zephyr.print("blinky on led0\n", .{});

    while (true) {
        try zephyr.sleepMs(500);
        try led.toggle();
        zephyr.print("toggle\n", .{});
    }
}
