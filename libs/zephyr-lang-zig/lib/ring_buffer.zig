const std = @import("std");
const testing = std.testing;

// Capacity must be a power of two so head/tail wrap to a bitmask AND
// `head -% tail` wraps to a valid length.
pub fn RingBuffer(comptime T: type, comptime capacity: usize) type {
    comptime {
        if (capacity == 0) {
            @compileError("RingBuffer: capacity must be > 0");
        }
        if ((capacity & (capacity - 1)) != 0) {
            @compileError("RingBuffer: capacity must be a power of two");
        }
    }

    return struct {
        const Self = @This();
        const mask: usize = capacity - 1;

        storage: [capacity]T = undefined,
        head: usize = 0,
        tail: usize = 0,

        pub const PushError = error{Full};

        pub fn len(self: *const Self) usize {
            return self.head -% self.tail;
        }

        pub fn isEmpty(self: *const Self) bool {
            return self.head == self.tail;
        }

        pub fn isFull(self: *const Self) bool {
            return self.len() == capacity;
        }

        pub fn push(self: *Self, item: T) PushError!void {
            if (self.isFull()) return error.Full;
            self.storage[self.head & mask] = item;
            self.head +%= 1;
        }

        // Returns the dropped item, or null if there was room.
        pub fn pushOverwrite(self: *Self, item: T) ?T {
            const dropped = if (self.isFull()) self.pop() else null;
            self.push(item) catch unreachable;
            return dropped;
        }

        pub fn pop(self: *Self) ?T {
            if (self.isEmpty()) return null;
            const item = self.storage[self.tail & mask];
            self.tail +%= 1;
            return item;
        }

        pub fn peek(self: *const Self) ?T {
            if (self.isEmpty()) return null;
            return self.storage[self.tail & mask];
        }

        pub fn clear(self: *Self) void {
            self.tail = self.head;
        }

        pub const Iterator = struct {
            ring: *const Self,
            offset: usize = 0,

            pub fn next(it: *Iterator) ?T {
                if (it.offset >= it.ring.len()) return null;
                const item = it.ring.storage[(it.ring.tail +% it.offset) & mask];
                it.offset += 1;
                return item;
            }
        };

        pub fn iterate(self: *const Self) Iterator {
            return .{ .ring = self };
        }
    };
}

test "RingBuffer basic push/pop FIFO order" {
    var rb = RingBuffer(u32, 4){};
    try testing.expect(rb.isEmpty());
    try rb.push(10);
    try rb.push(20);
    try rb.push(30);
    try testing.expectEqual(@as(usize, 3), rb.len());
    try testing.expectEqual(@as(?u32, 10), rb.pop());
    try testing.expectEqual(@as(?u32, 20), rb.pop());
    try testing.expectEqual(@as(?u32, 30), rb.pop());
    try testing.expectEqual(@as(?u32, null), rb.pop());
}

test "RingBuffer rejects when full" {
    var rb = RingBuffer(u8, 2){};
    try rb.push(1);
    try rb.push(2);
    try testing.expect(rb.isFull());
    try testing.expectError(error.Full, rb.push(3));
}

test "RingBuffer wraps cleanly over many cycles" {
    var rb = RingBuffer(u8, 4){};
    var i: u8 = 0;
    while (i < 100) : (i += 1) {
        try rb.push(i);
        try testing.expectEqual(@as(?u8, i), rb.pop());
    }
}

test "RingBuffer pushOverwrite drops oldest" {
    var rb = RingBuffer(u8, 2){};
    try testing.expectEqual(@as(?u8, null), rb.pushOverwrite(1));
    try testing.expectEqual(@as(?u8, null), rb.pushOverwrite(2));
    try testing.expectEqual(@as(?u8, 1), rb.pushOverwrite(3));
    try testing.expectEqual(@as(?u8, 2), rb.pop());
    try testing.expectEqual(@as(?u8, 3), rb.pop());
}

test "RingBuffer peek doesn't consume" {
    var rb = RingBuffer(u16, 4){};
    try rb.push(42);
    try testing.expectEqual(@as(?u16, 42), rb.peek());
    try testing.expectEqual(@as(?u16, 42), rb.peek());
    try testing.expectEqual(@as(usize, 1), rb.len());
}

test "RingBuffer iterator visits in FIFO order without consuming" {
    var rb = RingBuffer(u8, 8){};
    try rb.push(1);
    try rb.push(2);
    try rb.push(3);

    var sum: u32 = 0;
    var count: u32 = 0;
    var it = rb.iterate();
    while (it.next()) |item| {
        sum += item;
        count += 1;
    }
    try testing.expectEqual(@as(u32, 3), count);
    try testing.expectEqual(@as(u32, 6), sum);
    try testing.expectEqual(@as(usize, 3), rb.len());
}

test "RingBuffer clear" {
    var rb = RingBuffer(u8, 4){};
    try rb.push(1);
    try rb.push(2);
    rb.clear();
    try testing.expect(rb.isEmpty());
    try testing.expectEqual(@as(?u8, null), rb.pop());
}

test "RingBuffer over composite type" {
    const Event = struct { id: u32, payload: u64 };
    var rb = RingBuffer(Event, 4){};
    try rb.push(.{ .id = 1, .payload = 100 });
    try rb.push(.{ .id = 2, .payload = 200 });
    const first = rb.pop().?;
    try testing.expectEqual(@as(u32, 1), first.id);
    try testing.expectEqual(@as(u64, 100), first.payload);
}
