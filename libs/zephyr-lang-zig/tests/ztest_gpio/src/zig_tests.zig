const std = @import("std");
const zephyr = @import("zephyr");
const t = @import("test_helpers");

extern fn zig_gpio_emul_device() *anyopaque;
extern fn zig_gpio_emul_device_is_ready() bool;

// Real GPIO syscall implementations — directly callable as extern.
extern fn zig_gpio_pin_configure(port: *anyopaque, pin: u8, flags: u32) c_int;
extern fn zig_gpio_pin_set_raw(port: *anyopaque, pin: u8, value: c_int) c_int;
extern fn zig_gpio_pin_get_raw(port: *anyopaque, pin: u8) c_int;

// gpio_emul backend — these ARE real symbols (the wrappers in gpio_emul.h
// are static inlines that just bit-shift to BIT(pin) and call these).
extern fn gpio_emul_input_set_masked(port: *anyopaque, pins: u32, values: u32) c_int;
extern fn gpio_emul_output_get_masked(port: *anyopaque, pins: u32, values: *u32) c_int;
extern fn gpio_emul_flags_get(port: *anyopaque, pin: u8, flags: *u32) c_int;

// Flag constants from <zephyr/drivers/gpio.h>. Kept in sync via the bench
// test pattern of fail-loud-if-drift: if BIT(N) changes, gpio_emul_flags_get
// rejection paths fire below.
const GPIO_INPUT: u32 = 1 << 16;
const GPIO_OUTPUT: u32 = 1 << 17;
const GPIO_OUTPUT_INIT_LOW: u32 = 1 << 18;
const GPIO_OUTPUT_INIT_HIGH: u32 = 1 << 19;
const GPIO_OUTPUT_LOW: u32 = GPIO_OUTPUT | GPIO_OUTPUT_INIT_LOW;
const GPIO_OUTPUT_HIGH: u32 = GPIO_OUTPUT | GPIO_OUTPUT_INIT_HIGH;

const PIN_OUT: u8 = 0;
const PIN_IN: u8 = 1;

export fn zig_before() void {
    const dev = zig_gpio_emul_device();
    _ = zig_gpio_pin_configure(dev, PIN_OUT, GPIO_OUTPUT_LOW);
    _ = zig_gpio_pin_configure(dev, PIN_IN, GPIO_INPUT);
}

export fn zig_test_device_is_ready() void {
    t.zig_assert_true(zig_gpio_emul_device_is_ready());
}

export fn zig_test_output_set_high_reads_high() void {
    const dev = zig_gpio_emul_device();
    zephyr.checkError(zig_gpio_pin_set_raw(dev, PIN_OUT, 1)) catch t.zig_assert_unreachable();
    var v: u32 = 0;
    zephyr.checkError(gpio_emul_output_get_masked(dev, @as(u32, 1) << PIN_OUT, &v)) catch t.zig_assert_unreachable();
    t.zig_assert_u32_eq(v & (@as(u32, 1) << PIN_OUT), @as(u32, 1) << PIN_OUT);
}

export fn zig_test_output_set_low_reads_low() void {
    const dev = zig_gpio_emul_device();
    zephyr.checkError(zig_gpio_pin_set_raw(dev, PIN_OUT, 1)) catch t.zig_assert_unreachable();
    zephyr.checkError(zig_gpio_pin_set_raw(dev, PIN_OUT, 0)) catch t.zig_assert_unreachable();
    var v: u32 = 0;
    zephyr.checkError(gpio_emul_output_get_masked(dev, @as(u32, 1) << PIN_OUT, &v)) catch t.zig_assert_unreachable();
    t.zig_assert_u32_eq(v & (@as(u32, 1) << PIN_OUT), 0);
}

export fn zig_test_input_driven_high_reads_high() void {
    const dev = zig_gpio_emul_device();
    _ = gpio_emul_input_set_masked(dev, @as(u32, 1) << PIN_IN, @as(u32, 1) << PIN_IN);
    const val = zig_gpio_pin_get_raw(dev, PIN_IN);
    t.zig_assert_i64_eq(val, 1);
}

export fn zig_test_input_driven_low_reads_low() void {
    const dev = zig_gpio_emul_device();
    _ = gpio_emul_input_set_masked(dev, @as(u32, 1) << PIN_IN, @as(u32, 1) << PIN_IN);
    _ = gpio_emul_input_set_masked(dev, @as(u32, 1) << PIN_IN, 0);
    const val = zig_gpio_pin_get_raw(dev, PIN_IN);
    t.zig_assert_i64_eq(val, 0);
}

export fn zig_test_configure_output_then_flags_persist() void {
    const dev = zig_gpio_emul_device();
    zephyr.checkError(zig_gpio_pin_configure(dev, PIN_OUT, GPIO_OUTPUT)) catch t.zig_assert_unreachable();
    var flags: u32 = 0;
    zephyr.checkError(gpio_emul_flags_get(dev, PIN_OUT, &flags)) catch t.zig_assert_unreachable();
    t.zig_assert_u32_eq(flags & GPIO_OUTPUT, GPIO_OUTPUT);
}

export fn zig_test_multi_pin_output() void {
    const dev = zig_gpio_emul_device();
    zephyr.checkError(zig_gpio_pin_configure(dev, 2, GPIO_OUTPUT_LOW)) catch t.zig_assert_unreachable();
    zephyr.checkError(zig_gpio_pin_configure(dev, 3, GPIO_OUTPUT_LOW)) catch t.zig_assert_unreachable();
    _ = zig_gpio_pin_set_raw(dev, 2, 1);
    _ = zig_gpio_pin_set_raw(dev, 3, 1);
    var v: u32 = 0;
    _ = gpio_emul_output_get_masked(dev, (@as(u32, 1) << 2) | (@as(u32, 1) << 3), &v);
    t.zig_assert_u32_eq(v, (@as(u32, 1) << 2) | (@as(u32, 1) << 3));
}

export fn zig_test_output_init_high_starts_high() void {
    const dev = zig_gpio_emul_device();
    zephyr.checkError(zig_gpio_pin_configure(dev, 4, GPIO_OUTPUT_HIGH)) catch t.zig_assert_unreachable();
    var v: u32 = 0;
    _ = gpio_emul_output_get_masked(dev, @as(u32, 1) << 4, &v);
    t.zig_assert_u32_eq(v & (@as(u32, 1) << 4), @as(u32, 1) << 4);
}
