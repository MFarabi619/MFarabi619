const std = @import("std");
const pad = @import("pad.zig");

const c = @cImport({
    @cInclude("nuttx/config.h");
    @cInclude("fcntl.h");
    @cInclude("unistd.h");
    @cInclude("sys/ioctl.h");
    @cInclude("sys/mman.h");
    @cInclude("nuttx/video/fb.h");
});

const bg = 0x282828;
const cell_color = 0x3c3836;
const cell_active = 0x504945;
const cell_border = 0x665c54;
const active_border = 0xfe8019;
const arrow_color = 0xebdbb2;
const stop_color = 0xfb4934;

const cell_size: i32 = 130;
const cell_gap: i32 = 18;
const border_normal: i32 = 2;
const border_active: i32 = 4;
const stop_radius: i32 = 22;
const arrow_reach: f32 = 30;
const arrow_head_len: f32 = 17;
const arrow_head_width: f32 = 15;
const arrow_thickness: i32 = 3;

fn rgb565(color: u32) u16 {
    const r: u16 = @intCast((color >> 16) & 0xff);
    const g: u16 = @intCast((color >> 8) & 0xff);
    const b: u16 = @intCast(color & 0xff);
    return (r >> 3) << 11 | (g >> 2) << 5 | (b >> 3);
}

fn iround(v: f32) i32 {
    return @intFromFloat(@round(v));
}

pub const Panel = struct {
    fd: c_int,
    mem: [*]u16,
    len: usize,
    width: i32,
    height: i32,
    stride: usize,

    pub fn open() !Panel {
        const fd = c.open("/dev/fb0", c.O_RDWR);
        if (fd < 0) return error.Open;

        var vinfo: c.struct_fb_videoinfo_s = undefined;
        if (c.ioctl(fd, c.FBIOGET_VIDEOINFO, @intFromPtr(&vinfo)) < 0) return error.VideoInfo;

        var pinfo: c.struct_fb_planeinfo_s = undefined;
        if (c.ioctl(fd, c.FBIOGET_PLANEINFO, @intFromPtr(&pinfo)) < 0) return error.PlaneInfo;

        const mem = c.mmap(null, pinfo.fblen, c.PROT_READ | c.PROT_WRITE, c.MAP_SHARED, fd, 0);
        if (@intFromPtr(mem) == std.math.maxInt(usize)) return error.Mmap;

        return .{
            .fd = fd,
            .mem = @ptrCast(@alignCast(mem)),
            .len = pinfo.fblen,
            .width = vinfo.xres,
            .height = vinfo.yres,
            .stride = @as(usize, @intCast(pinfo.stride)) / 2,
        };
    }

    pub fn close(self: *Panel) void {
        _ = c.munmap(@ptrCast(self.mem), self.len);
        _ = c.close(self.fd);
    }

    pub fn hitTest(self: *const Panel, x: i32, y: i32) ?pad.Command {
        const total = 3 * cell_size + 2 * cell_gap;
        const x0 = @divTrunc(self.width - total, 2);
        const y0 = @divTrunc(self.height - total, 2);
        const rel_x = x - x0;
        const rel_y = y - y0;
        if (rel_x < 0 or rel_y < 0) return null;
        const col = @divTrunc(rel_x, cell_size + cell_gap);
        const row = @divTrunc(rel_y, cell_size + cell_gap);
        if (col > 2 or row > 2) return null;
        if (rel_x - col * (cell_size + cell_gap) >= cell_size) return null;
        if (rel_y - row * (cell_size + cell_gap) >= cell_size) return null;
        return .{
            .linear = 1 - @as(i8, @intCast(row)),
            .angular = 1 - @as(i8, @intCast(col)),
        };
    }

    fn px(self: *Panel, x: i32, y: i32, color: u32) void {
        if (x < 0 or y < 0 or x >= self.width or y >= self.height) return;
        self.mem[@as(usize, @intCast(y)) * self.stride + @as(usize, @intCast(x))] = rgb565(color);
    }

    fn fillRect(self: *Panel, x: i32, y: i32, w: i32, h: i32, color: u32) void {
        var yy = y;
        while (yy < y + h) : (yy += 1) {
            var xx = x;
            while (xx < x + w) : (xx += 1) self.px(xx, yy, color);
        }
    }

    fn border(self: *Panel, x: i32, y: i32, w: i32, h: i32, t: i32, color: u32) void {
        self.fillRect(x, y, w, t, color);
        self.fillRect(x, y + h - t, w, t, color);
        self.fillRect(x, y, t, h, color);
        self.fillRect(x + w - t, y, t, h, color);
    }

    fn fillDisc(self: *Panel, cx: i32, cy: i32, r: i32, color: u32) void {
        var yy: i32 = -r;
        while (yy <= r) : (yy += 1) {
            var xx: i32 = -r;
            while (xx <= r) : (xx += 1) {
                if (xx * xx + yy * yy <= r * r) self.px(cx + xx, cy + yy, color);
            }
        }
    }

    fn thickLine(self: *Panel, x0: f32, y0: f32, x1: f32, y1: f32, r: i32, color: u32) void {
        const dx = x1 - x0;
        const dy = y1 - y0;
        const len = @sqrt(dx * dx + dy * dy);
        const steps: i32 = @max(1, iround(len));
        var i: i32 = 0;
        while (i <= steps) : (i += 1) {
            const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps));
            self.fillDisc(iround(x0 + dx * t), iround(y0 + dy * t), r, color);
        }
    }

    fn arrow(self: *Panel, cx: i32, cy: i32, dx: i32, dy: i32, color: u32) void {
        var nx: f32 = @floatFromInt(dx);
        var ny: f32 = @floatFromInt(dy);
        const len = @sqrt(nx * nx + ny * ny);
        if (len > 0) {
            nx /= len;
            ny /= len;
        }
        const perpx = -ny;
        const perpy = nx;
        const fcx: f32 = @floatFromInt(cx);
        const fcy: f32 = @floatFromInt(cy);
        const tip_x = fcx + nx * arrow_reach;
        const tip_y = fcy + ny * arrow_reach;
        self.thickLine(fcx - nx * arrow_reach, fcy - ny * arrow_reach, tip_x, tip_y, arrow_thickness, color);
        self.thickLine(tip_x, tip_y, tip_x - nx * arrow_head_len + perpx * arrow_head_width, tip_y - ny * arrow_head_len + perpy * arrow_head_width, arrow_thickness, color);
        self.thickLine(tip_x, tip_y, tip_x - nx * arrow_head_len - perpx * arrow_head_width, tip_y - ny * arrow_head_len - perpy * arrow_head_width, arrow_thickness, color);
    }

    pub fn drawPad(self: *Panel, linear: i8, angular: i8) void {
        self.fillRect(0, 0, self.width, self.height, bg);
        const grid = pad.cells(linear, angular);
        const total = 3 * cell_size + 2 * cell_gap;
        const x0 = @divTrunc(self.width - total, 2);
        const y0 = @divTrunc(self.height - total, 2);
        var row: i32 = 0;
        while (row < 3) : (row += 1) {
            var col: i32 = 0;
            while (col < 3) : (col += 1) {
                const cell = grid[@intCast(row)][@intCast(col)];
                const cx = x0 + col * (cell_size + cell_gap);
                const cy = y0 + row * (cell_size + cell_gap);
                self.fillRect(cx, cy, cell_size, cell_size, if (cell.is_active) cell_active else cell_color);
                self.border(cx, cy, cell_size, cell_size, if (cell.is_active) border_active else border_normal, if (cell.is_active) active_border else cell_border);
                const ccx = cx + @divTrunc(cell_size, 2);
                const ccy = cy + @divTrunc(cell_size, 2);
                if (cell.is_stop) {
                    self.fillDisc(ccx, ccy, stop_radius, stop_color);
                } else {
                    self.arrow(ccx, ccy, cell.dx, cell.dy, arrow_color);
                }
            }
        }
    }
};
