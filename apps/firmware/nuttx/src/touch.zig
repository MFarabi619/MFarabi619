const c = @cImport({
    @cInclude("nuttx/config.h");
    @cInclude("fcntl.h");
    @cInclude("unistd.h");
    @cInclude("nuttx/input/touchscreen.h");
});

pub const Event = struct {
    pressed: bool,
    released: bool,
    x: i32,
    y: i32,
};

pub const Touch = struct {
    fd: c_int,

    pub fn open() !Touch {
        const fd = c.open("/dev/input0", c.O_RDONLY | c.O_NONBLOCK);
        if (fd < 0) return error.Open;
        return .{ .fd = fd };
    }

    pub fn close(self: *Touch) void {
        _ = c.close(self.fd);
    }

    pub fn read(self: *Touch) ?Event {
        var sample: c.struct_touch_sample_s = undefined;
        const n = c.read(self.fd, &sample, @sizeOf(c.struct_touch_sample_s));
        if (n < @as(isize, @sizeOf(c.struct_touch_sample_s)) or sample.npoints < 1) return null;

        const point = sample.point[0];
        const flags: u32 = point.flags;
        const down = (flags & (c.TOUCH_DOWN | c.TOUCH_MOVE)) != 0 and (flags & c.TOUCH_POS_VALID) != 0;
        return .{
            .pressed = down,
            .released = (flags & c.TOUCH_UP) != 0,
            .x = point.x,
            .y = point.y,
        };
    }
};
