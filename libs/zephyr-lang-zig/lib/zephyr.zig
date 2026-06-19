const std = @import("std");
const build_config = @import("build_config");
const timing = @import("timing");

pub const TICKS_PER_SEC: i64 = build_config.ticks_per_sec;

comptime {
    if (TICKS_PER_SEC <= 0) {
        @compileError("TICKS_PER_SEC must be positive; got " ++
            std.fmt.comptimePrint("{}", .{TICKS_PER_SEC}));
    }
}

pub const Timeout = extern struct {
    ticks: i64,

    pub fn fromMs(ms: i64) Timeout {
        return .{ .ticks = timing.ms_to_ticks(ms, TICKS_PER_SEC) };
    }

    pub fn forever() Timeout {
        return .{ .ticks = -1 };
    }

    pub fn noWait() Timeout {
        return .{ .ticks = 0 };
    }
};

comptime {
    if (@sizeOf(Timeout) != 8) {
        @compileError("Timeout layout drift — k_timeout_t no longer matches");
    }
}

pub const Error = error{
    NotPermitted,
    NotFound,
    IoError,
    TryAgain,
    NoMemory,
    Busy,
    NoDevice,
    InvalidArg,
    NotImplemented,
    TimedOut,
    NotConnected,
    AlreadyInProgress,
    Interrupted,
    Unknown,
};

/// Translate a negative Zephyr/Linux errno into a typed error. Non-negative
/// return codes are success.
pub fn checkError(rc: c_int) Error!void {
    if (rc >= 0) return;
    return switch (-rc) {
        1 => error.NotPermitted,
        2 => error.NotFound,
        5 => error.IoError,
        11 => error.TryAgain,
        12 => error.NoMemory,
        16 => error.Busy,
        19 => error.NoDevice,
        22 => error.InvalidArg,
        38 => error.NotImplemented,
        107 => error.NotConnected,
        110 => error.TimedOut,
        114 => error.AlreadyInProgress,
        else => error.Unknown,
    };
}

extern fn z_impl_k_sleep(timeout: Timeout) i32;
extern fn z_impl_k_uptime_ticks() i64;
extern fn zig_cycle_get_32() u32;
extern fn zig_cycle_hz() u32;

/// 32-bit CPU cycle counter. Wraps every (2^32 / cycleHz()) seconds —
/// at typical clock rates that's a few seconds, so it's only useful for
/// short interval measurements with wrapping subtraction.
pub fn cycleGet32() u32 {
    return zig_cycle_get_32();
}

pub fn cycleHz() u32 {
    return zig_cycle_hz();
}

pub fn sleepMs(ms: i64) Error!void {
    const remaining = z_impl_k_sleep(Timeout.fromMs(ms));
    if (remaining != 0) return error.Interrupted;
}

pub fn uptimeMs() i64 {
    return timing.ticks_to_ms(z_impl_k_uptime_ticks(), TICKS_PER_SEC);
}

extern fn printk(fmt: [*:0]const u8, ...) void;

const print_buffer_size = 128;

// Format with std.fmt then pass through "%s" so '%' in user data isn't
// reinterpreted as a printk format specifier.
pub fn print(comptime fmt: []const u8, args: anytype) void {
    var buf: [print_buffer_size]u8 = undefined;
    const formatted = std.fmt.bufPrintZ(&buf, fmt, args) catch {
        printk("[zig] print overflow (>%d bytes)\n", @as(c_int, print_buffer_size));
        return;
    };
    printk("%s", formatted.ptr);
}

pub fn say(msg: [*:0]const u8) void {
    printk("%s", msg);
}

extern fn zig_log_err(msg: [*:0]const u8) void;
extern fn zig_log_warn(msg: [*:0]const u8) void;
extern fn zig_log_info(msg: [*:0]const u8) void;
extern fn zig_log_debug(msg: [*:0]const u8) void;

/// Wire as `std.options.logFn`. Routes `std.log.scoped(.tag).info(...)`
/// through Zephyr's LOG_* macros. Requires C bridge functions
/// zig_log_err/warn/info/debug to be linked in.
pub fn logFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime fmt: []const u8,
    args: anytype,
) void {
    var buf: [256]u8 = undefined;
    const prefix = "[" ++ @tagName(scope) ++ "] ";
    const formatted = std.fmt.bufPrintZ(&buf, prefix ++ fmt, args) catch return;
    switch (level) {
        .err => zig_log_err(formatted.ptr),
        .warn => zig_log_warn(formatted.ptr),
        .info => zig_log_info(formatted.ptr),
        .debug => zig_log_debug(formatted.ptr),
    }
}

pub const AtomicCounter = struct {
    value: u32 align(4) = 0,

    pub fn increment(self: *AtomicCounter) u32 {
        return @atomicRmw(u32, &self.value, .Add, 1, .seq_cst);
    }

    pub fn load(self: *const AtomicCounter) u32 {
        return @atomicLoad(u32, &self.value, .seq_cst);
    }

    pub fn reset(self: *AtomicCounter) void {
        @atomicStore(u32, &self.value, 0, .seq_cst);
    }
};

extern fn k_aligned_alloc(alignment: usize, size: usize) ?*anyopaque;
extern fn k_free(ptr: ?*anyopaque) void;

pub const KMallocAllocator = struct {
    pub fn allocator(self: *KMallocAllocator) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .remap = remap,
                .free = free,
            },
        };
    }

    fn alloc(_: *anyopaque, len: usize, alignment: std.mem.Alignment, _: usize) ?[*]u8 {
        return @ptrCast(k_aligned_alloc(alignment.toByteUnits(), len));
    }

    fn resize(_: *anyopaque, buf: []u8, _: std.mem.Alignment, new_len: usize, _: usize) bool {
        return new_len <= buf.len;
    }

    fn remap(_: *anyopaque, buf: []u8, alignment: std.mem.Alignment, new_len: usize, _: usize) ?[*]u8 {
        const new_ptr = k_aligned_alloc(alignment.toByteUnits(), new_len) orelse return null;
        const copy_len = @min(buf.len, new_len);
        @memcpy(@as([*]u8, @ptrCast(new_ptr))[0..copy_len], buf[0..copy_len]);
        k_free(buf.ptr);
        return @ptrCast(new_ptr);
    }

    fn free(_: *anyopaque, buf: []u8, _: std.mem.Alignment, _: usize) void {
        k_free(buf.ptr);
    }
};

extern fn z_impl_k_mutex_init(m: *anyopaque) c_int;
extern fn z_impl_k_mutex_lock(m: *anyopaque, timeout: Timeout) c_int;
extern fn z_impl_k_mutex_unlock(m: *anyopaque) c_int;

pub const Mutex = struct {
    handle: *anyopaque,

    /// Wrap a handle already initialized by C (e.g. K_MUTEX_DEFINE).
    pub fn fromHandle(handle: *anyopaque) Mutex {
        return .{ .handle = handle };
    }

    /// Initialize a fresh k_mutex at the given handle.
    pub fn init(handle: *anyopaque) Error!Mutex {
        try checkError(z_impl_k_mutex_init(handle));
        return .{ .handle = handle };
    }

    pub fn lock(self: Mutex, timeout: Timeout) Error!void {
        try checkError(z_impl_k_mutex_lock(self.handle, timeout));
    }

    pub fn unlock(self: Mutex) Error!void {
        try checkError(z_impl_k_mutex_unlock(self.handle));
    }
};

/// ABI-matched mirror of `struct gpio_dt_spec` (port: *const device, pin: u8,
/// dt_flags: u16). Construct one from a devicetree gpio handle:
///   const led = GpioDtSpec.fromDt(dt.leds.led_0.gpios);
pub const GpioDtSpec = extern struct {
    port: *const anyopaque,
    pin: u8,
    dt_flags: u16,

    pub fn fromDt(gpios: anytype) GpioDtSpec {
        return .{
            .port = @ptrCast(gpios.ph._device),
            .pin = @intCast(gpios.pin),
            .dt_flags = @intCast(gpios.flags),
        };
    }

    pub fn isReady(self: *const GpioDtSpec) bool {
        return zig_gpio_is_ready_dt(self);
    }

    pub fn configure(self: *const GpioDtSpec, flags: u32) Error!void {
        try checkError(zig_gpio_pin_configure_dt(self, flags));
    }

    pub fn toggle(self: *const GpioDtSpec) Error!void {
        try checkError(zig_gpio_pin_toggle_dt(self));
    }
};

extern fn zig_gpio_is_ready_dt(spec: *const GpioDtSpec) bool;
extern fn zig_gpio_pin_configure_dt(spec: *const GpioDtSpec, flags: u32) c_int;
extern fn zig_gpio_pin_toggle_dt(spec: *const GpioDtSpec) c_int;

/// GPIO_OUTPUT_INACTIVE = GPIO_OUTPUT | GPIO_OUTPUT_INIT_LOGICAL | GPIO_OUTPUT_INIT_LOW
/// Pulled from gpio.h via translate-c probe; mirrors bit positions 17/18/20.
pub const GPIO_OUTPUT_INACTIVE: u32 = (1 << 17) | (1 << 18) | (1 << 20);

extern fn z_impl_k_sem_init(s: *anyopaque, initial: c_uint, limit: c_uint) c_int;
extern fn z_impl_k_sem_take(s: *anyopaque, timeout: Timeout) c_int;
extern fn z_impl_k_sem_give(s: *anyopaque) void;
extern fn zig_sem_count(s: *anyopaque) c_uint;

pub const Semaphore = struct {
    handle: *anyopaque,

    /// Wrap a handle already initialized by C (e.g. K_SEM_DEFINE).
    pub fn fromHandle(handle: *anyopaque) Semaphore {
        return .{ .handle = handle };
    }

    pub fn init(handle: *anyopaque, initial: c_uint, limit: c_uint) Error!Semaphore {
        try checkError(z_impl_k_sem_init(handle, initial, limit));
        return .{ .handle = handle };
    }

    pub fn take(self: Semaphore, timeout: Timeout) Error!void {
        try checkError(z_impl_k_sem_take(self.handle, timeout));
    }

    pub fn give(self: Semaphore) void {
        z_impl_k_sem_give(self.handle);
    }

    pub fn count(self: Semaphore) c_uint {
        return zig_sem_count(self.handle);
    }
};
