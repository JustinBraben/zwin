const std = @import("std");
const zwin = @import("zwin");

pub fn main() !void {
    const file_name = "test_write_read.txt";
    const test_data = "Hello, Memory Mapped World!";
    {
        const file = try std.fs.cwd().createFile(file_name, .{});
        defer file.close();
        try file.writeAll(test_data);
    }

    // Map the file
    var mapped_file = try zwin.FileMapped.init(file_name, .{
        .buff_size = @intCast(test_data.len),
        .file_map_start = 0,
        .creation_disposition = .OPEN_EXISTING
    });
    defer mapped_file.deinit();

    // Read and verify data
    const mapped_data = try mapped_file.getData();
    std.debug.print("{s}\n", .{mapped_data});

    const typed_data = try mapped_file.getDataAs(u8);
    std.debug.print("{s}\n", .{typed_data});
}
