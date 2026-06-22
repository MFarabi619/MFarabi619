const std = @import("std");
const build_config = @import("build_config");
const timing = @import("timing");
pub const sys = @import("sys");

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

/// Translate a negative Zephyr errno into a typed error. Non-negative is success.
pub fn checkError(rc: c_int) Error!void {
    if (rc >= 0) return;
    return switch (-rc) {
        sys.EPERM => error.NotPermitted,
        sys.ENOENT => error.NotFound,
        sys.EIO => error.IoError,
        sys.EAGAIN => error.TryAgain,
        sys.ENOMEM => error.NoMemory,
        sys.EBUSY => error.Busy,
        sys.ENODEV => error.NoDevice,
        sys.EINVAL => error.InvalidArg,
        sys.ENOSYS => error.NotImplemented,
        sys.ETIMEDOUT => error.TimedOut,
        sys.ENOTCONN => error.NotConnected,
        sys.EALREADY => error.AlreadyInProgress,
        else => error.Unknown,
    };
}

/// 32-bit CPU cycle counter. Wraps every (2^32 / cycleHz()) seconds —
/// at typical clock rates that's a few seconds, so it's only useful for
/// short interval measurements with wrapping subtraction.
pub fn cycleGet32() u32 {
    return sys.sys_clock_cycle_get_32();
}

pub fn cycleHz() u32 {
    return sys.sys_clock_hw_cycles_per_sec();
}

pub fn sleepMs(ms: i64) Error!void {
    const timeout = Timeout.fromMs(ms);
    const remaining = sys.z_impl_k_sleep(@bitCast(timeout));
    if (remaining != 0) return error.Interrupted;
}

pub fn uptimeMs() i64 {
    return timing.ticks_to_ms(sys.z_impl_k_uptime_ticks(), TICKS_PER_SEC);
}

extern fn printk(fmt: [*:0]const u8, ...) void;

const print_buffer_size = 128;

// Format via std.fmt then route through "%s" so '%' in user data isn't reinterpreted.
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

pub const bdd = struct {
    pub fn given(narration: [*:0]const u8) void {
        printk("  \x1b[1;30;46m[GIVEN]\x1b[0m \x1b[36m%s\x1b[0m\n", narration);
    }
    pub fn when(narration: [*:0]const u8) void {
        printk("    \x1b[1;30;103m[WHEN]\x1b[0m \x1b[33m%s\x1b[0m\n", narration);
    }
    pub fn then(narration: [*:0]const u8) void {
        printk("      \x1b[1;30;105m[THEN]\x1b[0m \x1b[35m%s\x1b[0m\n", narration);
    }
    pub fn @"and"(narration: [*:0]const u8) void {
        printk("      \x1b[1;30;105m[AND]\x1b[0m  \x1b[35m%s\x1b[0m\n", narration);
    }
};

extern fn log_err(msg: [*:0]const u8) void;
extern fn log_warn(msg: [*:0]const u8) void;
extern fn log_info(msg: [*:0]const u8) void;
extern fn log_debug(msg: [*:0]const u8) void;

/// Wire as `std.options.logFn` to route `std.log` through Zephyr's LOG_* macros.
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
        .err => log_err(formatted.ptr),
        .warn => log_warn(formatted.ptr),
        .info => log_info(formatted.ptr),
        .debug => log_debug(formatted.ptr),
    }
}

pub const Mutex = struct {
    handle: [*c]sys.k_mutex,

    pub fn fromHandle(handle: *anyopaque) Mutex {
        return .{ .handle = @ptrCast(@alignCast(handle)) };
    }

    pub fn init(handle: *anyopaque) Error!Mutex {
        const typed: [*c]sys.k_mutex = @ptrCast(@alignCast(handle));
        try checkError(sys.z_impl_k_mutex_init(typed));
        return .{ .handle = typed };
    }

    pub fn lock(self: Mutex, timeout: Timeout) Error!void {
        try checkError(sys.z_impl_k_mutex_lock(self.handle, @bitCast(timeout)));
    }

    pub fn unlock(self: Mutex) Error!void {
        try checkError(sys.z_impl_k_mutex_unlock(self.handle));
    }
};

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
        return sys.z_impl_device_is_ready(@ptrCast(@alignCast(self.port)));
    }

    pub fn configure(self: *const GpioDtSpec, flags: u32) Error!void {
        const combined: u32 = @as(u32, self.dt_flags) | flags;
        try checkError(sys.z_impl_gpio_pin_configure(@ptrCast(@alignCast(self.port)), self.pin, combined));
    }

    pub fn toggle(self: *const GpioDtSpec) Error!void {
        try checkError(sys.z_impl_gpio_pin_toggle(@ptrCast(@alignCast(self.port)), self.pin));
    }
};

pub const GPIO_OUTPUT_INACTIVE: u32 = @intCast(sys.GPIO_OUTPUT_INACTIVE);

pub const Semaphore = struct {
    handle: [*c]sys.k_sem,

    pub fn fromHandle(handle: *anyopaque) Semaphore {
        return .{ .handle = @ptrCast(@alignCast(handle)) };
    }

    pub fn init(handle: *anyopaque, initial: c_uint, limit: c_uint) Error!Semaphore {
        const typed: [*c]sys.k_sem = @ptrCast(@alignCast(handle));
        try checkError(sys.z_impl_k_sem_init(typed, initial, limit));
        return .{ .handle = typed };
    }

    pub fn take(self: Semaphore, timeout: Timeout) Error!void {
        try checkError(sys.z_impl_k_sem_take(self.handle, @bitCast(timeout)));
    }

    pub fn give(self: Semaphore) void {
        sys.z_impl_k_sem_give(self.handle);
    }

    pub fn count(self: Semaphore) c_uint {
        return sys.z_impl_k_sem_count_get(self.handle);
    }
};
