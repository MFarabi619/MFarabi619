const std = @import("std");
const zitadel = @import("zitadel");

pub fn main(init: std.process.Init) !void {
    // Prints to stderr, ignoring potential errors.
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
    try zitadel.bufferedPrint(init.io);

    const x: i32 = 5;
    const y: i32 = 16;
    // const z: i32 = zitadel.add(x, y);
    const z: i32 = zitadel.add_c(x, y);

    // Zig 0.16+ IO: avoid global std.io helpers.
    // Use the IO handles provided by std.process.Init, and buffer explicitly.
    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("{d} + {d} = {d}\n", .{ x, y, z });
    try stdout.flush();
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa); // Try commenting this out and see if zig detects the memory leak!
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}

test "fuzz example" {
    const Context = struct {
        fn testOne(context: @This(), input: []const u8) anyerror!void {
            _ = context;
            // Try passing `--fuzz` to `zig build test` and see if it manages to fail this test case!
            try std.testing.expect(!std.mem.eql(u8, "canyoufindme", input));
        }
    };
    try std.testing.fuzz(Context{}, Context.testOne, .{});
}
