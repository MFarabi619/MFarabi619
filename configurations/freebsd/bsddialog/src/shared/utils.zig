const std = @import("std");
const c = @import("../c/bindings.zig").c;

pub fn serialize_checklist_selections(items: []const c.struct_bsddialog_menuitem, output_buffer: []u8) ![]const u8 {
    var fixed_buffer_stream = std.io.fixedBufferStream(output_buffer);
    const stream_writer = fixed_buffer_stream.writer();

    var is_first_selected_item = true;
    for (items) |item| {
        if (!item.on) continue;

        const item_name = std.mem.span(item.name);
        if (!is_first_selected_item) {
            try stream_writer.writeByte(' ');
        }
        is_first_selected_item = false;

        const item_name_has_space = std.mem.indexOfScalar(u8, item_name, ' ') != null;
        if (item_name_has_space) {
            try stream_writer.writeByte('"');
        }
        try stream_writer.writeAll(item_name);
        if (item_name_has_space) {
            try stream_writer.writeByte('"');
        }
    }

    return fixed_buffer_stream.getWritten();
}

pub fn allocate_formatted_c_string(allocator: std.mem.Allocator, comptime format_string: []const u8, format_arguments: anytype) ![:0]u8 {
    const formatted_text = try std.fmt.allocPrint(allocator, format_string, format_arguments);
    defer allocator.free(formatted_text);
    return allocator.dupeZ(u8, formatted_text);
}
