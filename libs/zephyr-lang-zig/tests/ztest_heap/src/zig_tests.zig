const std = @import("std");
const zephyr = @import("zephyr");
const t = @import("test_helpers");

export fn zig_test_heap_basic_alloc_free() void {
    var state = zephyr.KMallocAllocator{};
    const allocator = state.allocator();

    const buf = allocator.alloc(u8, 64) catch {
        t.zig_assert_true(false);
        return;
    };
    defer allocator.free(buf);

    @memset(buf, 0xAB);
    var sum: u32 = 0;
    for (buf) |b| sum += b;
    t.zig_assert_usize_eq(sum, 64 * 0xAB);
}

export fn zig_test_heap_alignment() void {
    var state = zephyr.KMallocAllocator{};
    const allocator = state.allocator();

    const buf = allocator.alignedAlloc(u8, .@"16", 32) catch {
        t.zig_assert_true(false);
        return;
    };
    defer allocator.free(buf);

    t.zig_assert_true(@intFromPtr(buf.ptr) % 16 == 0);
}

export fn zig_test_heap_arraylist() void {
    var state = zephyr.KMallocAllocator{};
    const allocator = state.allocator();

    var list: std.ArrayList(u32) = .empty;
    defer list.deinit(allocator);

    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        list.append(allocator, i) catch {
            t.zig_assert_true(false);
            return;
        };
    }

    t.zig_assert_usize_eq(list.items.len, 100);

    var sum: u32 = 0;
    for (list.items) |v| sum += v;
    t.zig_assert_usize_eq(sum, (99 * 100) / 2);
}

export fn zig_test_heap_alloc_print() void {
    var state = zephyr.KMallocAllocator{};
    const allocator = state.allocator();

    const msg = std.fmt.allocPrint(allocator, "count={d}", .{42}) catch {
        t.zig_assert_true(false);
        return;
    };
    defer allocator.free(msg);

    t.zig_assert_usize_eq(msg.len, 8);
    t.zig_assert_true(std.mem.eql(u8, msg, "count=42"));
}

export fn zig_test_heap_many_cycles() void {
    var state = zephyr.KMallocAllocator{};
    const allocator = state.allocator();

    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        const size = 16 + (i % 128);
        const buf = allocator.alloc(u8, size) catch {
            t.zig_assert_true(false);
            return;
        };
        @memset(buf, @intCast(i % 256));
        allocator.free(buf);
    }
}
