const std = @import("std");
const dt = @import("dt");
const zephyr = @import("zephyr");
const sys = zephyr.sys;

const status_led = zephyr.GpioDtSpec.fromDt(dt.aliases.status_led.*.gpios);
const eeprom = dt.aliases.eeprom_0;
const rtc = dt.aliases.rtc;

const SAMPLE_COUNT = 16;
const CALIBRATION_OFFSET: u32 = 100;
const EEPROM_OFFSET: c_long = 0;

const SensorStats = extern struct {
    min: u32,
    mean: u32,
    max: u32,
    crc32: u32,
};

extern fn rust_compute_stats(samples: [*]const u32, len: usize) SensorStats;
extern fn c_sum16(samples: [*]const u32, len: usize) u16;

pub const panic = zephyr.panic;

fn blinkStatusLed() !void {
    if (!status_led.isReady()) return error.LedNotReady;
    try status_led.configure(zephyr.GPIO_OUTPUT_INACTIVE);
    for (0..3) |_| {
        try status_led.toggle();
        try zephyr.sleepMs(20);
    }
    zephyr.print("gpio: status_led toggled 3x\n", .{});
}

fn roundTripCalibration() !u32 {
    const bytes_to_write = std.mem.toBytes(CALIBRATION_OFFSET);
    try zephyr.call(sys.eeprom_write, .{
        zephyr.devOf(eeprom), EEPROM_OFFSET, &bytes_to_write, bytes_to_write.len,
    });
    var bytes_read: [@sizeOf(u32)]u8 = .{0} ** @sizeOf(u32);
    try zephyr.call(sys.eeprom_read, .{
        zephyr.devOf(eeprom), EEPROM_OFFSET, &bytes_read, bytes_read.len,
    });
    const calibration = std.mem.bytesToValue(u32, &bytes_read);
    zephyr.print("eeprom: calibration=0x{x:0>8}\n", .{calibration});
    return calibration;
}

fn setAndReadRtc() !void {
    var desired_time = std.mem.zeroes(sys.rtc_time);
    desired_time.tm_year = 126; // years since 1900
    desired_time.tm_mon = 5; // 0-indexed: June
    desired_time.tm_mday = 23;
    desired_time.tm_hour = 12;
    desired_time.tm_isdst = -1;
    try zephyr.call(sys.rtc_set_time, .{ zephyr.devOf(rtc), &desired_time });

    var actual_time: sys.rtc_time = undefined;
    try zephyr.call(sys.rtc_get_time, .{ zephyr.devOf(rtc), &actual_time });

    const year: u32 = @intCast(actual_time.tm_year + 1900);
    const month: u32 = @intCast(actual_time.tm_mon + 1);
    const day: u32 = @intCast(actual_time.tm_mday);
    const hour: u32 = @intCast(actual_time.tm_hour);
    const minute: u32 = @intCast(actual_time.tm_min);
    const second: u32 = @intCast(actual_time.tm_sec);
    zephyr.print("rtc: {d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}\n", .{
        year, month, day, hour, minute, second,
    });
}

fn computeStats(calibration: u32) void {
    var samples: [SAMPLE_COUNT]u32 = undefined;
    for (&samples, 0..) |*sample, index| sample.* = calibration + @as(u32, @intCast(index));

    const stats = rust_compute_stats(&samples, samples.len);
    zephyr.print("rust: min={d} mean={d} max={d} crc32=0x{x:0>8}\n", .{
        stats.min, stats.mean, stats.max, stats.crc32,
    });

    const sum16 = c_sum16(&samples, samples.len);
    zephyr.print("c: sum16=0x{x:0>4}\n", .{sum16});
}

fn app() !void {
    zephyr.print("ffi_rust_with_c: boot\n", .{});
    try blinkStatusLed();
    const calibration = try roundTripCalibration();
    try setAndReadRtc();
    computeStats(calibration);
    zephyr.print("ffi_rust_with_c: done\n", .{});
}

export fn main() c_int {
    return zephyr.runApp(app);
}
