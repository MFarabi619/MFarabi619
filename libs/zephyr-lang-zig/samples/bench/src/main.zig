const std = @import("std");
const zephyr = @import("zephyr");
const RingBuffer = @import("ring_buffer").RingBuffer;

fn bench(comptime name: []const u8, iterations: u32, comptime body: anytype) void {
    const start = zephyr.cycleGet32();
    var i: u32 = 0;
    while (i < iterations) : (i += 1) {
        body();
    }
    const end = zephyr.cycleGet32();

    const elapsed_cycles: u64 = end -% start;
    const hz: u64 = zephyr.cycleHz();
    const total_ns = @divTrunc(elapsed_cycles * 1_000_000_000, hz);
    const per_op_ns = @divTrunc(total_ns, iterations);

    zephyr.print("[bench] {s:<20} {d:>8} iters, {d:>8} cycles, {d:>6} ns/op\n", .{
        name,
        iterations,
        elapsed_cycles,
        per_op_ns,
    });
}

var counter = zephyr.AtomicCounter{};

fn bench_atomic_increment() void {
    _ = counter.increment();
}

var ring: RingBuffer(u32, 16) = .{};

fn bench_ring_push_pop() void {
    ring.push(42) catch unreachable;
    _ = ring.pop();
}

fn bench_bufprintz() void {
    var buf: [64]u8 = undefined;
    _ = std.fmt.bufPrintZ(&buf, "value={d}", .{42}) catch unreachable;
}

var alloc_state = zephyr.KMallocAllocator{};

fn bench_alloc_free() void {
    const allocator = alloc_state.allocator();
    const buf = allocator.alloc(u8, 32) catch return;
    allocator.free(buf);
}

var baseline_sink: u32 = 0;

fn bench_baseline_loop() void {
    _ = @atomicLoad(u32, &baseline_sink, .seq_cst);
}

export fn main() c_int {
    zephyr.print("=== zephyr-lang-zig bench ===\n", .{});
    zephyr.print("cycle clock: {d} Hz\n\n", .{zephyr.cycleHz()});

    bench("baseline_loop", 100_000, bench_baseline_loop);
    bench("atomic_increment", 100_000, bench_atomic_increment);
    bench("ring_push_pop", 100_000, bench_ring_push_pop);
    bench("bufPrintZ_fmt", 100_000, bench_bufprintz);
    bench("kmalloc_free_32B", 10_000, bench_alloc_free);

    zephyr.print("\n=== bench done ===\n", .{});
    return 0;
}
