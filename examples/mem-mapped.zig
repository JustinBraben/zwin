const std = @import("std");
const zwin = @import("zwin");

pub fn main() !void {
    const file_name = "test_write_read.txt";
    var example_mmap = try zwin.FileMapped.init(file_name, .{ 
        .buff_size = 27,
        .creation_disposition = .OPEN_EXISTING
    });
    defer example_mmap.deinit();

    try example_mmap.createMapping();
    try example_mmap.mapView();
    // const data_ptr = try example_mmap.getDataPointer();
    // std.debug.print("Value at pointer: {}\n", .{data_ptr.*});
}
