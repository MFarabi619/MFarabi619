const dt = @import("dt");
const zephyr = @import("zephyr");
const sys = zephyr.sys;

const strip = dt.aliases.led_strip;
const num_pixels: usize = @intCast(strip.*.chain_length);
const brightness: u8 = 0x40;
const delay_ms: i64 = 200;

const colors = [_]sys.led_rgb{
    .{ .r = brightness, .g = 0, .b = 0 },
    .{ .r = 0, .g = brightness, .b = 0 },
    .{ .r = 0, .g = 0, .b = brightness },
};

const off: sys.led_rgb = .{ .r = 0, .g = 0, .b = 0 };
var pixels: [num_pixels]sys.led_rgb = [_]sys.led_rgb{off} ** num_pixels;

pub const panic = zephyr.panic;

fn app() !void {
    zephyr.say("Displaying pattern on strip\n");

    var color: usize = 0;
    while (true) {
        var cursor: usize = 0;
        while (cursor < pixels.len) : (cursor += 1) {
            @memset(&pixels, off);
            pixels[cursor] = colors[color];
            try zephyr.call(sys.led_strip_update_rgb, .{ zephyr.devOf(strip), &pixels, pixels.len });
            try zephyr.sleepMs(delay_ms);
        }
        color = (color + 1) % colors.len;
    }
}

export fn main() c_int {
    return zephyr.runApp(app);
}
