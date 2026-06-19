const std = @import("std");
const testing = std.testing;

pub fn ms_to_ticks(ms: i64, ticks_per_sec: i64) i64 {
    return std.math.divCeil(i64, ms * ticks_per_sec, 1000) catch 0;
}

pub fn ticks_to_ms(ticks: i64, ticks_per_sec: i64) i64 {
    return std.math.divFloor(i64, ticks * 1000, ticks_per_sec) catch 0;
}

test "ms_to_ticks rounds 1000ms at 100Hz to 100 ticks" {
    try testing.expectEqual(@as(i64, 100), ms_to_ticks(1000, 100));
}

test "ms_to_ticks rounds 1ms at 100Hz up to 1 tick" {
    try testing.expectEqual(@as(i64, 1), ms_to_ticks(1, 100));
}

test "ms_to_ticks rounds 10ms at 100Hz exactly to 1 tick" {
    try testing.expectEqual(@as(i64, 1), ms_to_ticks(10, 100));
}

test "ms_to_ticks rounds 11ms at 100Hz up to 2 ticks" {
    try testing.expectEqual(@as(i64, 2), ms_to_ticks(11, 100));
}

test "ms_to_ticks at 1000Hz" {
    try testing.expectEqual(@as(i64, 1000), ms_to_ticks(1000, 1000));
    try testing.expectEqual(@as(i64, 1), ms_to_ticks(1, 1000));
}

test "ms_to_ticks zero ms is zero ticks" {
    try testing.expectEqual(@as(i64, 0), ms_to_ticks(0, 100));
}

test "ticks_to_ms is exact inverse at boundary rates" {
    try testing.expectEqual(@as(i64, 1000), ticks_to_ms(100, 100));
    try testing.expectEqual(@as(i64, 1000), ticks_to_ms(1000, 1000));
}

test "ticks_to_ms floors fractional ms" {
    // At 1024Hz, 1 tick = 0.977ms, floors to 0
    try testing.expectEqual(@as(i64, 0), ticks_to_ms(1, 1024));
    // At 1024Hz, 1024 ticks = exactly 1000ms
    try testing.expectEqual(@as(i64, 1000), ticks_to_ms(1024, 1024));
    // At 1024Hz, 1023 ticks = 999.02ms, floors to 999
    try testing.expectEqual(@as(i64, 999), ticks_to_ms(1023, 1024));
}
