const builtin = @import("builtin");
const zephyr = @import("zephyr");
const RingBuffer = @import("ring_buffer").RingBuffer;

const TickEvent = struct {
    count: u32,
    uptime_ms: i64,
};

const Phase = union(enum) {
    booting,
    running: u32,
};

export fn main() c_int {
    zephyr.print("tick_loop on {s}\n", .{@tagName(builtin.cpu.arch)});

    var events = RingBuffer(TickEvent, 8){};
    var ticks = zephyr.AtomicCounter{};
    var phase: Phase = .booting;

    while (true) {
        zephyr.sleepMs(1000) catch |err| {
            zephyr.print("sleep interrupted: {s}\n", .{@errorName(err)});
            continue;
        };

        const count = ticks.increment() + 1;
        phase = .{ .running = count };

        if (events.pushOverwrite(.{ .count = count, .uptime_ms = zephyr.uptimeMs() })) |dropped| {
            zephyr.print("dropped oldest event (count={})\n", .{dropped.count});
        }

        zephyr.print("tick {d:>3} at {}ms, buffered={}, phase={s}\n", .{
            count,
            zephyr.uptimeMs(),
            events.len(),
            @tagName(phase),
        });
    }
}
