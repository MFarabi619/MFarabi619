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
    zephyr.bdd.given("a K_MUTEX_DEFINE'd mutex");
    zephyr.bdd.when("lock(.forever) then unlock are called in sequence");
    zephyr.bdd.then("both calls return without error");

    const m = zephyr.Mutex.fromHandle(get_test_mutex());
    m.lock(zephyr.Timeout.forever()) catch t.zig_assert_unreachable();
    m.unlock() catch t.zig_assert_unreachable();
    t.zig_assert_true(true);
}

export fn zig_test_mutex_reentrant() void {
    zephyr.bdd.given("a Zephyr mutex (recursive by design)");
    zephyr.bdd.when("the same thread locks twice and unlocks twice");
    zephyr.bdd.then("all four calls succeed");

    const m = zephyr.Mutex.fromHandle(get_test_mutex());
    m.lock(zephyr.Timeout.forever()) catch t.zig_assert_unreachable();
    m.lock(zephyr.Timeout.forever()) catch t.zig_assert_unreachable();
    m.unlock() catch t.zig_assert_unreachable();
    m.unlock() catch t.zig_assert_unreachable();
    t.zig_assert_true(true);
}

export fn zig_test_mutex_runtime_init() void {
    zephyr.bdd.given("a fresh k_mutex handle (not K_MUTEX_DEFINE'd)");
    zephyr.bdd.when("Mutex.init initializes it at runtime");
    zephyr.bdd.then("lock with a 100ms timeout succeeds");

    const m = zephyr.Mutex.init(get_runtime_mutex()) catch {
        t.zig_assert_unreachable();
    };
    m.lock(zephyr.Timeout.fromMs(100)) catch t.zig_assert_unreachable();
    m.unlock() catch t.zig_assert_unreachable();
    t.zig_assert_true(true);
}

export fn zig_test_sem_take_give() void {
    zephyr.bdd.given("an empty semaphore");
    zephyr.bdd.when("we give then immediately take");
    zephyr.bdd.then("count returns to 0");

    const s = zephyr.Semaphore.fromHandle(get_test_sem());
    s.give();
    s.take(zephyr.Timeout.forever()) catch t.zig_assert_unreachable();
    t.zig_assert_u32_eq(s.count(), 0);
}

export fn zig_test_sem_take_no_wait_empty() void {
    zephyr.bdd.given("an empty semaphore");
    zephyr.bdd.when("take is called with a .noWait timeout");
    zephyr.bdd.then("it returns either Busy or TryAgain");

    const s = zephyr.Semaphore.fromHandle(get_test_sem());
    s.take(zephyr.Timeout.noWait()) catch |err| {
        t.zig_assert_true(err == zephyr.Error.Busy or err == zephyr.Error.TryAgain);
        return;
    };
    t.zig_assert_unreachable();
}

export fn zig_test_sem_count() void {
    zephyr.bdd.given("an empty semaphore");
    zephyr.bdd.when("give is called three times in a row");
    zephyr.bdd.then("count is 3");

    const s = zephyr.Semaphore.fromHandle(get_test_sem());
    s.give();
    s.give();
    s.give();
    t.zig_assert_u32_eq(s.count(), 3);
}

export fn zig_test_sem_runtime_init() void {
    zephyr.bdd.given("a fresh k_sem handle");
    zephyr.bdd.when("Semaphore.init creates it with initial=2 limit=5");
    zephyr.bdd.then("count is 2 and two takes drain it to 0");

    const s = zephyr.Semaphore.init(get_runtime_sem(), 2, 5) catch {
        t.zig_assert_unreachable();
    };
    t.zig_assert_u32_eq(s.count(), 2);
    s.take(zephyr.Timeout.noWait()) catch t.zig_assert_unreachable();
    s.take(zephyr.Timeout.noWait()) catch t.zig_assert_unreachable();
    t.zig_assert_u32_eq(s.count(), 0);
}

export fn zig_test_check_error_success() void {
    zephyr.bdd.given("checkError, the errno -> Zig error translator");
    zephyr.bdd.when("non-negative return codes (0 and 7) are passed");
    zephyr.bdd.then("no error is raised");

    zephyr.checkError(0) catch t.zig_assert_unreachable();
    zephyr.checkError(7) catch t.zig_assert_unreachable();
    t.zig_assert_true(true);
}

export fn zig_test_check_error_invalid_arg() void {
    zephyr.bdd.given("checkError");
    zephyr.bdd.when("the errno -22 (EINVAL) is passed");
    zephyr.bdd.then("it raises Error.InvalidArg");

    zephyr.checkError(-22) catch |err| {
        t.zig_assert_true(err == zephyr.Error.InvalidArg);
        return;
    };
    t.zig_assert_unreachable();
}

export fn zig_test_check_error_busy() void {
    zephyr.bdd.given("checkError");
    zephyr.bdd.when("the errno -16 (EBUSY) is passed");
    zephyr.bdd.then("it raises Error.Busy");

    zephyr.checkError(-16) catch |err| {
        t.zig_assert_true(err == zephyr.Error.Busy);
        return;
    };
    t.zig_assert_unreachable();
}

export fn zig_test_check_error_unknown() void {
    zephyr.bdd.given("checkError");
    zephyr.bdd.when("an unmapped negative errno (-9999) is passed");
    zephyr.bdd.then("it raises Error.Unknown as the catch-all");

    zephyr.checkError(-9999) catch |err| {
        t.zig_assert_true(err == zephyr.Error.Unknown);
        return;
    };
    t.zig_assert_unreachable();
}
