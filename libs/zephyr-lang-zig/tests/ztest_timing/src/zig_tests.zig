const zephyr = @import("zephyr");
const timing = @import("timing");
const RingBuffer = @import("ring_buffer").RingBuffer;

extern fn zig_assert_i64_eq(actual: i64, expected: i64) void;
extern fn zig_assert_true(condition: bool) void;
extern fn zig_assert_usize_eq(actual: usize, expected: usize) void;

// -- timing --

export fn zig_test_ms_to_ticks_100hz_1000ms() void {
    zephyr.bdd.given("a 100Hz tick rate");
    zephyr.bdd.when("1000ms is converted to ticks");
    zephyr.bdd.then("the result is exactly 100");

    zig_assert_i64_eq(timing.ms_to_ticks(1000, 100), 100);
}

export fn zig_test_ms_to_ticks_100hz_1ms() void {
    zephyr.bdd.given("a 100Hz tick rate (10ms per tick)");
    zephyr.bdd.when("1ms is converted to ticks");
    zephyr.bdd.then("the result rounds up to 1 (never zero)");

    zig_assert_i64_eq(timing.ms_to_ticks(1, 100), 1);
}

export fn zig_test_ms_to_ticks_100hz_10ms() void {
    zephyr.bdd.given("a 100Hz tick rate (10ms per tick)");
    zephyr.bdd.when("an exact-period 10ms is converted");
    zephyr.bdd.then("the result is exactly 1 tick");

    zig_assert_i64_eq(timing.ms_to_ticks(10, 100), 1);
}

export fn zig_test_ms_to_ticks_100hz_11ms() void {
    zephyr.bdd.given("a 100Hz tick rate");
    zephyr.bdd.when("11ms (just over one period) is converted");
    zephyr.bdd.then("the result rounds up to 2 ticks");

    zig_assert_i64_eq(timing.ms_to_ticks(11, 100), 2);
}

export fn zig_test_ms_to_ticks_1000hz() void {
    zephyr.bdd.given("a 1000Hz tick rate (1ms per tick)");
    zephyr.bdd.when("1000ms and 1ms are converted");
    zephyr.bdd.then("the results are 1000 and 1 respectively");

    zig_assert_i64_eq(timing.ms_to_ticks(1000, 1000), 1000);
    zig_assert_i64_eq(timing.ms_to_ticks(1, 1000), 1);
}

export fn zig_test_ticks_to_ms_roundtrip() void {
    zephyr.bdd.given("tick counts equal to the tick frequency");
    zephyr.bdd.when("converted to milliseconds");
    zephyr.bdd.then("the result is exactly 1000ms regardless of rate");

    zig_assert_i64_eq(timing.ticks_to_ms(100, 100), 1000);
    zig_assert_i64_eq(timing.ticks_to_ms(1024, 1024), 1000);
}

// -- ring_buffer --

export fn zig_test_ring_buffer_fifo_order() void {
    zephyr.bdd.given("a 4-slot RingBuffer(u32)");
    zephyr.bdd.when("10, 20, 30 are pushed and then popped");
    zephyr.bdd.then("they come out in FIFO order and a fourth pop yields null");

    var rb = RingBuffer(u32, 4){};
    rb.push(10) catch unreachable;
    rb.push(20) catch unreachable;
    rb.push(30) catch unreachable;
    zig_assert_usize_eq(rb.len(), 3);
    zig_assert_i64_eq(@intCast(rb.pop().?), 10);
    zig_assert_i64_eq(@intCast(rb.pop().?), 20);
    zig_assert_i64_eq(@intCast(rb.pop().?), 30);
    zig_assert_true(rb.pop() == null);
}

export fn zig_test_ring_buffer_overwrite() void {
    zephyr.bdd.given("a 2-slot ring buffer at capacity (holds 1, 2)");
    zephyr.bdd.when("pushOverwrite is called with a third value 3");
    zephyr.bdd.then("the oldest entry (1) is returned as the dropped value");

    var rb = RingBuffer(u8, 2){};
    zig_assert_true(rb.pushOverwrite(1) == null);
    zig_assert_true(rb.pushOverwrite(2) == null);
    const dropped = rb.pushOverwrite(3);
    zig_assert_true(dropped != null);
    zig_assert_i64_eq(@intCast(dropped.?), 1);
}

export fn zig_test_ring_buffer_full_returns_error() void {
    zephyr.bdd.given("a 2-slot ring buffer at capacity");
    zephyr.bdd.when("plain push (no overwrite) is called");
    zephyr.bdd.then("error.Full is returned");

    var rb = RingBuffer(u8, 2){};
    rb.push(1) catch unreachable;
    rb.push(2) catch unreachable;
    if (rb.push(3)) |_| {
        zig_assert_true(false);
    } else |err| {
        zig_assert_true(err == error.Full);
    }
}

export fn zig_test_ring_buffer_iterator() void {
    zephyr.bdd.given("an 8-slot RingBuffer holding 1, 2, 3");
    zephyr.bdd.when("the iterator walks all entries");
    zephyr.bdd.then("the sum is 6 and len is unchanged");

    var rb = RingBuffer(u16, 8){};
    rb.push(1) catch unreachable;
    rb.push(2) catch unreachable;
    rb.push(3) catch unreachable;

    var sum: u32 = 0;
    var it = rb.iterate();
    while (it.next()) |item| {
        sum += item;
    }
    zig_assert_i64_eq(@intCast(sum), 6);
    zig_assert_usize_eq(rb.len(), 3);
}
