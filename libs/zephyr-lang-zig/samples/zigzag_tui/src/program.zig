const std = @import("std");
const zephyr = @import("zephyr");
const zz = @import("zigzag");

var persistent_buf: [256 * 1024]u8 = undefined;
var frame_buf: [4 * 1024 * 1024]u8 = undefined;

extern fn zig_uart_poll_in(c: *u8) c_int;

pub const Context = struct {
    allocator: std.mem.Allocator,
    persistent_allocator: std.mem.Allocator,
    width: u16 = 80,
    height: u16 = 24,
    elapsed: u64 = 0,
    frame: usize = 0,
    last_delta: u64 = 0,

    pub fn fps(self: *const Context) f64 {
        if (self.last_delta == 0) return 0.0;
        return 1_000_000_000.0 / @as(f64, @floatFromInt(self.last_delta));
    }
};

const TerminalSize = struct { width: u16, height: u16 };

fn queryTerminalSize() TerminalSize {
    zephyr.say("\x1B[s\x1B[999;999H\x1B[6n\x1B[u");

    var buf: [32]u8 = undefined;
    var n: usize = 0;
    const deadline_ms = zephyr.uptimeMs() + 250;

    while (n < buf.len) {
        if (zephyr.uptimeMs() >= deadline_ms) break;
        var byte: u8 = 0;
        if (zig_uart_poll_in(&byte) == 0) {
            buf[n] = byte;
            n += 1;
            if (byte == 'R') break;
        }
    }

    const fallback: TerminalSize = .{ .width = 80, .height = 24 };
    if (n < 6 or buf[0] != 0x1B or buf[1] != '[') return fallback;

    var i: usize = 2;
    var row: u16 = 0;
    while (i < n and buf[i] >= '0' and buf[i] <= '9') : (i += 1) {
        row = row *% 10 +% (buf[i] - '0');
    }
    if (i >= n or buf[i] != ';') return fallback;
    i += 1;
    var col: u16 = 0;
    while (i < n and buf[i] >= '0' and buf[i] <= '9') : (i += 1) {
        col = col *% 10 +% (buf[i] - '0');
    }
    if (i >= n or buf[i] != 'R') return fallback;
    if (row == 0 or col == 0) return fallback;

    return .{ .width = col, .height = row };
}

const InputParser = struct {
    state: State = .normal,

    const State = enum { normal, esc, csi };

    pub fn feed(self: *InputParser, byte: u8) ?zz.KeyEvent {
        return switch (self.state) {
            .normal => self.feedNormal(byte),
            .esc => self.feedEsc(byte),
            .csi => self.feedCsi(byte),
        };
    }

    fn feedNormal(self: *InputParser, byte: u8) ?zz.KeyEvent {
        switch (byte) {
            0x1B => {
                self.state = .esc;
                return null;
            },
            0x09 => return zz.KeyEvent{ .key = .tab },
            0x0D, 0x0A => return zz.KeyEvent{ .key = .enter },
            0x7F, 0x08 => return zz.KeyEvent{ .key = .backspace },
            0x20 => return zz.KeyEvent{ .key = .space },
            0x01...0x07, 0x0B...0x0C, 0x0E...0x1A => return zz.KeyEvent{
                .key = .{ .char = byte + 0x60 },
                .modifiers = .{ .ctrl = true },
            },
            0x21...0x7E => return zz.KeyEvent{ .key = .{ .char = byte } },
            else => return null,
        }
    }

    fn feedEsc(self: *InputParser, byte: u8) ?zz.KeyEvent {
        if (byte == '[') {
            self.state = .csi;
            return null;
        }
        self.state = .normal;
        return zz.KeyEvent{ .key = .escape };
    }

    fn feedCsi(self: *InputParser, byte: u8) ?zz.KeyEvent {
        if (byte < 0x40) {
            return null;
        }
        self.state = .normal;
        return switch (byte) {
            'A' => zz.KeyEvent{ .key = .up },
            'B' => zz.KeyEvent{ .key = .down },
            'C' => zz.KeyEvent{ .key = .right },
            'D' => zz.KeyEvent{ .key = .left },
            'H' => zz.KeyEvent{ .key = .home },
            'F' => zz.KeyEvent{ .key = .end },
            'Z' => zz.KeyEvent{ .key = .tab, .modifiers = .{ .shift = true } },
            else => null,
        };
    }
};

pub fn Program(comptime ModelType: type) type {
    return struct {
        const Self = @This();

        pub fn init() Self {
            return .{};
        }

        pub fn run(self: *Self) !void {
            _ = self;

            var persistent_fba = std.heap.FixedBufferAllocator.init(&persistent_buf);
            var frame_fba = std.heap.FixedBufferAllocator.init(&frame_buf);

            zephyr.say("\x1B[?1049h\x1B[?25l\x1B[2J\x1B[H");

            const size = queryTerminalSize();

            var ctx: Context = .{
                .allocator = frame_fba.allocator(),
                .persistent_allocator = persistent_fba.allocator(),
                .width = size.width,
                .height = size.height,
            };

            var model: ModelType = undefined;
            _ = model.init(&ctx);
            defer model.deinit();

            var input_parser: InputParser = .{};

            const start_ms = zephyr.uptimeMs();
            var last_frame_ms: i64 = start_ms;
            const tick_target_ms: i64 = 16;

            while (true) {
                var byte: u8 = 0;
                while (zig_uart_poll_in(&byte) == 0) {
                    if (input_parser.feed(byte)) |key_event| {
                        const cmd = model.update(.{ .key = key_event }, &ctx);
                        if (cmd == .quit) {
                            zephyr.say("\x1B[?25h\x1B[?1049l");
                            return;
                        }
                    }
                }

                const now = zephyr.uptimeMs();
                const delta_ms: i64 = now - last_frame_ms;
                last_frame_ms = now;

                const elapsed_ns: i64 = (now - start_ms) * std.time.ns_per_ms;
                ctx.elapsed = @intCast(elapsed_ns);
                ctx.frame += 1;
                ctx.last_delta = @intCast(@max(delta_ms, 1) * std.time.ns_per_ms);

                _ = model.update(.{ .tick = .{ .timestamp = elapsed_ns, .delta = ctx.last_delta } }, &ctx);

                frame_fba.reset();
                const body = model.view(&ctx);

                var newline_count: usize = 0;
                for (body) |body_byte| {
                    if (body_byte == '\n') newline_count += 1;
                }
                const out_len = body.len + newline_count * 3;
                const out = try frame_fba.allocator().allocSentinel(u8, out_len, 0);
                var write_idx: usize = 0;
                for (body) |body_byte| {
                    if (body_byte == '\n') {
                        out[write_idx] = 0x1B;
                        out[write_idx + 1] = '[';
                        out[write_idx + 2] = 'K';
                        write_idx += 3;
                    }
                    out[write_idx] = body_byte;
                    write_idx += 1;
                }

                zephyr.say("\x1B[H");
                zephyr.say(out);
                zephyr.say("\x1B[J");

                const sleep_until = last_frame_ms + tick_target_ms;
                const now2 = zephyr.uptimeMs();
                if (now2 < sleep_until) {
                    try zephyr.sleepMs(sleep_until - now2);
                }
            }
        }

        pub fn deinit(self: *Self) void {
            _ = self;
        }
    };
}
