const zephyr = @import("zephyr");
const timing = @import("timing");
const RingBuffer = @import("ring_buffer").RingBuffer;
const assert = @import("test_helpers");

// -- timing --

export fn zig_test_ms_to_ticks_100hz_1000ms() void {
    zephyr.bdd.given("a 100Hz tick rate");
    zephyr.bdd.when("1000ms is converted to ticks");
    zephyr.bdd.then("the result is exactly 100");

    assert.eq(timing.ms_to_ticks(1000, 100), 100);
}

export fn zig_test_ms_to_ticks_100hz_1ms() void {
    zephyr.bdd.given("a 100Hz tick rate (10ms per tick)");
    zephyr.bdd.when("1ms is converted to ticks");
    zephyr.bdd.then("the result rounds up to 1 (never zero)");

    assert.eq(timing.ms_to_ticks(1, 100), 1);
}

export fn zig_test_ms_to_ticks_100hz_10ms() void {
    zephyr.bdd.given("a 100Hz tick rate (10ms per tick)");
    zephyr.bdd.when("an exact-period 10ms is converted");
    zephyr.bdd.then("the result is exactly 1 tick");

    assert.eq(timing.ms_to_ticks(10, 100), 1);
}

export fn zig_test_ms_to_ticks_100hz_11ms() void {
    zephyr.bdd.given("a 100Hz tick rate");
    zephyr.bdd.when("11ms (just over one period) is converted");
    zephyr.bdd.then("the result rounds up to 2 ticks");

    assert.eq(timing.ms_to_ticks(11, 100), 2);
}

export fn zig_test_ms_to_ticks_1000hz() void {
    zephyr.bdd.given("a 1000Hz tick rate (1ms per tick)");
    zephyr.bdd.when("1000ms and 1ms are converted");
    zephyr.bdd.then("the results are 1000 and 1 respectively");

    assert.eq(timing.ms_to_ticks(1000, 1000), 1000);
    assert.eq(timing.ms_to_ticks(1, 1000), 1);
}

export fn zig_test_ticks_to_ms_roundtrip() void {
    zephyr.bdd.given("tick counts equal to the tick frequency");
    zephyr.bdd.when("converted to milliseconds");
    zephyr.bdd.then("the result is exactly 1000ms regardless of rate");

    assert.eq(timing.ticks_to_ms(100, 100), 1000);
    assert.eq(timing.ticks_to_ms(1024, 1024), 1000);
}

// -- ring_buffer --

export fn zig_test_ring_buffer_fifo_order() void {
    zephyr.bdd.given("a 4-slot RingBuffer(u32)");
    zephyr.bdd.when("10, 20, 30 are pushed and then popped");
    zephyr.bdd.then("they come out in FIFO order and a fourth pop yields null");

    var ring = RingBuffer(u32, 4){};
    ring.push(10) catch unreachable;
    ring.push(20) catch unreachable;
    ring.push(30) catch unreachable;
    assert.eq(ring.len(), 3);
    assert.eq(ring.pop().?, 10);
    assert.eq(ring.pop().?, 20);
    assert.eq(ring.pop().?, 30);
    assert.isTrue(ring.pop() == null);
}

export fn zig_test_ring_buffer_overwrite() void {
    zephyr.bdd.given("a 2-slot ring buffer at capacity (holds 1, 2)");
    zephyr.bdd.when("pushOverwrite is called with a third value 3");
    zephyr.bdd.then("the oldest entry (1) is returned as the dropped value");

    var ring = RingBuffer(u8, 2){};
    assert.isTrue(ring.pushOverwrite(1) == null);
    assert.isTrue(ring.pushOverwrite(2) == null);
    const dropped = ring.pushOverwrite(3);
    assert.isTrue(dropped != null);
    assert.eq(dropped.?, 1);
}

export fn zig_test_ring_buffer_full_returns_error() void {
    zephyr.bdd.given("a 2-slot ring buffer at capacity");
    zephyr.bdd.when("plain push (no overwrite) is called");
    zephyr.bdd.then("error.Full is returned");

    var ring = RingBuffer(u8, 2){};
    ring.push(1) catch unreachable;
    ring.push(2) catch unreachable;
    if (ring.push(3)) |_| {
        assert.isTrue(false);
    } else |err| {
        assert.isTrue(err == error.Full);
    }
}

export fn zig_test_ring_buffer_iterator() void {
    zephyr.bdd.given("an 8-slot RingBuffer holding 1, 2, 3");
    zephyr.bdd.when("the iterator walks all entries");
    zephyr.bdd.then("the sum is 6 and len is unchanged");

    var ring = RingBuffer(u16, 8){};
    ring.push(1) catch unreachable;
    ring.push(2) catch unreachable;
    ring.push(3) catch unreachable;

    var sum: u32 = 0;
    var it = ring.iterate();
    while (it.next()) |item| {
        sum += item;
    }
    assert.eq(sum, 6);
    assert.eq(ring.len(), 3);
}
