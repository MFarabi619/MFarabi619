//! By convention, root.zig is the root source file when making a library.
//!
//! This file exposes reusable functionality and tests.
//! It does NOT assume global stdout access.
//! Instead, IO is passed in explicitly (Zig 0.16 style).

const std = @import("std");

const arithmetic = @cImport({
    @cInclude("arithmetic/arithmetic.h");
});

/// Prints a message using a buffered writer.
///
/// Stdout is for the actual output of your application.
/// For example, if you are implementing gzip, then only the compressed
/// bytes should be sent to stdout, not debugging messages.
///
/// We use a buffer to reduce syscalls and improve performance.
pub fn bufferedPrint(io: std.Io) !void {
    var stdout_buffer: [1024]u8 = undefined;

    // Create a buffered writer targeting stdout.
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    try stdout.print("Run `zig build test` to run the tests.\n", .{});

    // Always flush buffered output!
    try stdout.flush();
}

/// Simple addition function to demonstrate exported library logic.
pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

pub fn add_c(x: i32, y: i32) i32 {
    return arithmetic.add(x, y);
}

test "basic add functionality" {
    try std.testing.expect(add(3, 7) == 10);
}
