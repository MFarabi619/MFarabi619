const timing = @import("timing");
const RingBuffer = @import("ring_buffer").RingBuffer;

extern fn zig_assert_i64_eq(actual: i64, expected: i64) void;
extern fn zig_assert_true(condition: bool) void;
extern fn zig_assert_usize_eq(actual: usize, expected: usize) void;

// -- timing --

export fn zig_test_ms_to_ticks_100hz_1000ms() void {
    zig_assert_i64_eq(timing.ms_to_ticks(1000, 100), 100);
}

export fn zig_test_ms_to_ticks_100hz_1ms() void {
    zig_assert_i64_eq(timing.ms_to_ticks(1, 100), 1);
}

export fn zig_test_ms_to_ticks_100hz_10ms() void {
    zig_assert_i64_eq(timing.ms_to_ticks(10, 100), 1);
}

export fn zig_test_ms_to_ticks_100hz_11ms() void {
    zig_assert_i64_eq(timing.ms_to_ticks(11, 100), 2);
}

export fn zig_test_ms_to_ticks_1000hz() void {
    zig_assert_i64_eq(timing.ms_to_ticks(1000, 1000), 1000);
    zig_assert_i64_eq(timing.ms_to_ticks(1, 1000), 1);
}

export fn zig_test_ticks_to_ms_roundtrip() void {
    zig_assert_i64_eq(timing.ticks_to_ms(100, 100), 1000);
    zig_assert_i64_eq(timing.ticks_to_ms(1024, 1024), 1000);
}

// -- ring_buffer (sanity on the target's actual ABI) --

export fn zig_test_ring_buffer_fifo_order() void {
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
    var rb = RingBuffer(u8, 2){};
    zig_assert_true(rb.pushOverwrite(1) == null);
    zig_assert_true(rb.pushOverwrite(2) == null);
    const dropped = rb.pushOverwrite(3);
    zig_assert_true(dropped != null);
    zig_assert_i64_eq(@intCast(dropped.?), 1);
}

export fn zig_test_ring_buffer_full_returns_error() void {
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
