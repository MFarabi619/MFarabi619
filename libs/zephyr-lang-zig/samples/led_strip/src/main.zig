const dt = @import("dt");
const zephyr = @import("zephyr");

const LedRgb = extern struct { r: u8 = 0, g: u8 = 0, b: u8 = 0 };

extern fn bridge_led_strip_update_rgb(dev: *const anyopaque, pixels: [*]LedRgb, num_pixels: usize) c_int;

const strip_node = dt.aliases.led_strip;
const STRIP_NUM_PIXELS: usize = @intCast(strip_node.*.chain_length);
const BRIGHTNESS: u8 = 0x40;
const DELAY_MS: i64 = 50;

const colors = [_]LedRgb{
    .{ .r = BRIGHTNESS, .g = 0, .b = 0 },
    .{ .r = 0, .g = BRIGHTNESS, .b = 0 },
    .{ .r = 0, .g = 0, .b = BRIGHTNESS },
};

var pixels: [STRIP_NUM_PIXELS]LedRgb = .{LedRgb{}} ** STRIP_NUM_PIXELS;

export fn main() c_int {
    const strip: *const anyopaque = @ptrCast(strip_node.*._device);
    zephyr.say("Displaying pattern on strip\n");

    var color: usize = 0;
    while (true) {
        var cursor: usize = 0;
        while (cursor < pixels.len) : (cursor += 1) {
            for (&pixels) |*p| p.* = .{};
            pixels[cursor] = colors[color];
            _ = bridge_led_strip_update_rgb(strip, &pixels, pixels.len);
            zephyr.sleepMs(DELAY_MS) catch return 1;
        }
        color = (color + 1) % colors.len;
    }
}
