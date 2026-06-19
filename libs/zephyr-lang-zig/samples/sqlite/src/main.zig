const std = @import("std");
const zephyr = @import("zephyr");

extern fn sqlite3_libversion() [*:0]const u8;
extern fn sqlite3_open(filename: [*:0]const u8, ppDb: *?*anyopaque) c_int;
extern fn sqlite3_close(db: ?*anyopaque) c_int;
extern fn sqlite3_exec(
    db: ?*anyopaque,
    sql: [*:0]const u8,
    callback: ?*const fn (?*anyopaque, c_int, [*c][*c]u8, [*c][*c]u8) callconv(.c) c_int,
    arg: ?*anyopaque,
    errmsg: ?*?[*:0]u8,
) c_int;
extern fn sqlite3_errmsg(db: ?*anyopaque) [*:0]const u8;
extern fn sqlite3_free(p: ?*anyopaque) void;

const DB_PATH = "/lfs/test.db";

fn print_row(_: ?*anyopaque, n_cols: c_int, values: [*c][*c]u8, names: [*c][*c]u8) callconv(.c) c_int {
    var i: c_int = 0;
    while (i < n_cols) : (i += 1) {
        const idx: usize = @intCast(i);
        const name = std.mem.sliceTo(names[idx], 0);
        const value = if (values[idx] != null) std.mem.sliceTo(values[idx], 0) else "NULL";
        zephyr.print("  {s} = {s}\n", .{ name, value });
    }
    zephyr.print("---\n", .{});
    return 0;
}

fn exec_logged(db: ?*anyopaque, sql: [*:0]const u8, callback: ?*const fn (?*anyopaque, c_int, [*c][*c]u8, [*c][*c]u8) callconv(.c) c_int) c_int {
    var err: ?[*:0]u8 = null;
    const rc = sqlite3_exec(db, sql, callback, null, &err);
    if (rc != 0) {
        const msg = if (err) |e| std.mem.sliceTo(e, 0) else std.mem.sliceTo(sqlite3_errmsg(db), 0);
        zephyr.print("ERR ({d}): {s}\n", .{ rc, msg });
        sqlite3_free(@ptrCast(err));
    }
    return rc;
}

export fn main() c_int {
    zephyr.print("SQLite {s} from Zig\n", .{std.mem.sliceTo(sqlite3_libversion(), 0)});

    var db: ?*anyopaque = null;
    if (sqlite3_open(DB_PATH, &db) != 0) {
        zephyr.print("open {s}: {s}\n", .{ DB_PATH, std.mem.sliceTo(sqlite3_errmsg(db), 0) });
        _ = sqlite3_close(db);
        return -1;
    }
    zephyr.print("opened {s}\n", .{DB_PATH});

    _ = exec_logged(db, "CREATE TABLE IF NOT EXISTS readings (id INTEGER PRIMARY KEY, temperature REAL, label TEXT)", null);
    _ = exec_logged(db, "INSERT INTO readings (temperature, label) VALUES (21.5, 'kitchen')", null);
    _ = exec_logged(db, "INSERT INTO readings (temperature, label) VALUES (19.0, 'outside')", null);
    _ = exec_logged(db, "SELECT id, temperature, label FROM readings", print_row);

    _ = sqlite3_close(db);
    zephyr.print("sqlite sample done\n", .{});
    return 0;
}
