const dt = @import("dt");
const zephyr = @import("zephyr");

const led = zephyr.GpioDtSpec.fromDt(dt.aliases.led0.*.gpios);

export fn main() c_int {
    if (!led.isReady()) {
        zephyr.print("led0 not ready\n", .{});
        return 1;
    }
    led.configure(zephyr.GPIO_OUTPUT_INACTIVE) catch {
        zephyr.print("led0 configure failed\n", .{});
        return 1;
    };

    zephyr.print("blinky on led0\n", .{});

    while (true) {
        zephyr.sleepMs(500) catch return 1;
        led.toggle() catch return 1;
        zephyr.print("toggle\n", .{});
    }
}
