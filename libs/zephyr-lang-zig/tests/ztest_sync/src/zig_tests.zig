const std = @import("std");
const zephyr = @import("zephyr");
const t = @import("test_helpers");

extern fn get_test_mutex() *anyopaque;
extern fn get_test_sem() *anyopaque;
extern fn get_runtime_mutex() *anyopaque;
extern fn get_runtime_sem() *anyopaque;

fn drain(sem: zephyr.Semaphore) void {
    while (sem.count() > 0) {
        sem.take(zephyr.Timeout.noWait()) catch break;
    }
}

export fn zig_before() void {
    drain(zephyr.Semaphore.fromHandle(get_test_sem()));
}

export fn zig_test_mutex_lock_unlock() void {
    const m = zephyr.Mutex.fromHandle(get_test_mutex());
    m.lock(zephyr.Timeout.forever()) catch t.zig_assert_unreachable();
    m.unlock() catch t.zig_assert_unreachable();
    t.zig_assert_true(true);
}

export fn zig_test_mutex_reentrant() void {
    const m = zephyr.Mutex.fromHandle(get_test_mutex());
    m.lock(zephyr.Timeout.forever()) catch t.zig_assert_unreachable();
    m.lock(zephyr.Timeout.forever()) catch t.zig_assert_unreachable();
    m.unlock() catch t.zig_assert_unreachable();
    m.unlock() catch t.zig_assert_unreachable();
    t.zig_assert_true(true);
}

export fn zig_test_mutex_runtime_init() void {
    const m = zephyr.Mutex.init(get_runtime_mutex()) catch {
        t.zig_assert_unreachable();
    };
    m.lock(zephyr.Timeout.fromMs(100)) catch t.zig_assert_unreachable();
    m.unlock() catch t.zig_assert_unreachable();
    t.zig_assert_true(true);
}

export fn zig_test_sem_take_give() void {
    const s = zephyr.Semaphore.fromHandle(get_test_sem());
    s.give();
    s.take(zephyr.Timeout.forever()) catch t.zig_assert_unreachable();
    t.zig_assert_u32_eq(s.count(), 0);
}

export fn zig_test_sem_take_no_wait_empty() void {
    const s = zephyr.Semaphore.fromHandle(get_test_sem());
    s.take(zephyr.Timeout.noWait()) catch |err| {
        t.zig_assert_true(err == zephyr.Error.Busy or err == zephyr.Error.TryAgain);
        return;
    };
    t.zig_assert_unreachable();
}

export fn zig_test_sem_count() void {
    const s = zephyr.Semaphore.fromHandle(get_test_sem());
    s.give();
    s.give();
    s.give();
    t.zig_assert_u32_eq(s.count(), 3);
}

export fn zig_test_sem_runtime_init() void {
    const s = zephyr.Semaphore.init(get_runtime_sem(), 2, 5) catch {
        t.zig_assert_unreachable();
    };
    t.zig_assert_u32_eq(s.count(), 2);
    s.take(zephyr.Timeout.noWait()) catch t.zig_assert_unreachable();
    s.take(zephyr.Timeout.noWait()) catch t.zig_assert_unreachable();
    t.zig_assert_u32_eq(s.count(), 0);
}

export fn zig_test_check_error_success() void {
    zephyr.checkError(0) catch t.zig_assert_unreachable();
    zephyr.checkError(7) catch t.zig_assert_unreachable();
    t.zig_assert_true(true);
}

export fn zig_test_check_error_invalid_arg() void {
    zephyr.checkError(-22) catch |err| {
        t.zig_assert_true(err == zephyr.Error.InvalidArg);
        return;
    };
    t.zig_assert_unreachable();
}

export fn zig_test_check_error_busy() void {
    zephyr.checkError(-16) catch |err| {
        t.zig_assert_true(err == zephyr.Error.Busy);
        return;
    };
    t.zig_assert_unreachable();
}

export fn zig_test_check_error_unknown() void {
    zephyr.checkError(-9999) catch |err| {
        t.zig_assert_true(err == zephyr.Error.Unknown);
        return;
    };
    t.zig_assert_unreachable();
}
