const std = @import("std");
const zephyr = @import("zephyr");
const assert = @import("test_helpers");

export fn zig_test_heap_basic_alloc_free() void {
    zephyr.bdd.given("std.heap.c_allocator wired to Zephyr's libc malloc");
    zephyr.bdd.when("64 bytes are allocated and memset to 0xAB");
    zephyr.bdd.then("the byte-sum equals 64 * 0xAB");

    const allocator = std.heap.c_allocator;

    const buf = allocator.alloc(u8, 64) catch {
        assert.isTrue(false);
        return;
    };
    defer allocator.free(buf);

    @memset(buf, 0xAB);
    var sum: u32 = 0;
    for (buf) |b| sum += b;
    assert.eq(sum, 64 * 0xAB);
}

export fn zig_test_heap_alignment() void {
    zephyr.bdd.given("std.heap.c_allocator");
    zephyr.bdd.when("an aligned alloc requests 32 bytes at 16-byte alignment");
    zephyr.bdd.then("the returned pointer is 16-byte aligned");

    const allocator = std.heap.c_allocator;

    const buf = allocator.alignedAlloc(u8, .@"16", 32) catch {
        assert.isTrue(false);
        return;
    };
    defer allocator.free(buf);

    assert.isTrue(@intFromPtr(buf.ptr) % 16 == 0);
}

export fn zig_test_heap_arraylist() void {
    zephyr.bdd.given("a heap-backed std.ArrayList(u32)");
    zephyr.bdd.when("100 sequential integers are appended");
    zephyr.bdd.then("len is 100 and the sum equals (99 * 100) / 2");

    const allocator = std.heap.c_allocator;

    var list: std.ArrayList(u32) = .empty;
    defer list.deinit(allocator);

    var i: u32 = 0;
    while (i < 100) : (i += 1) {
        list.append(allocator, i) catch {
            assert.isTrue(false);
            return;
        };
    }

    assert.eq(list.items.len, 100);

    var sum: u32 = 0;
    for (list.items) |v| sum += v;
    assert.eq(sum, (99 * 100) / 2);
}

export fn zig_test_heap_alloc_print() void {
    zephyr.bdd.given("a heap-backed allocator");
    zephyr.bdd.when("std.fmt.allocPrint formats \"count={d}\" with arg 42");
    zephyr.bdd.then("the resulting heap string equals \"count=42\"");

    const allocator = std.heap.c_allocator;

    const msg = std.fmt.allocPrint(allocator, "count={d}", .{42}) catch {
        assert.isTrue(false);
        return;
    };
    defer allocator.free(msg);

    assert.eq(msg.len, 8);
    assert.isTrue(std.mem.eql(u8, msg, "count=42"));
}

export fn zig_test_heap_many_cycles() void {
    zephyr.bdd.given("std.heap.c_allocator");
    zephyr.bdd.when("1000 alloc/free cycles run with varying sizes 16..143");
    zephyr.bdd.then("none of them OOM or assert");

    const allocator = std.heap.c_allocator;

    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        const size = 16 + (i % 128);
        const buf = allocator.alloc(u8, size) catch {
            assert.isTrue(false);
            return;
        };
        @memset(buf, @intCast(i % 256));
        allocator.free(buf);
    }
}
