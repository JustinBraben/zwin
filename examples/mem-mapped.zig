const std = @import("std");
const zwin = @import("zwin");

pub fn main() !void {
    const file_name = "fmtest.txt";
    var example_mmap = try zwin.FileMapped.init(file_name, .{});
    defer example_mmap.deinit();

    try example_mmap.createMapping();
    try example_mmap.mapView();
    const data_ptr = try example_mmap.getDataPointer();
    std.debug.print("Value at pointer: {}\n", .{data_ptr.*});
}
