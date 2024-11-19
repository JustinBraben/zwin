const std = @import("std");
const zwin = @import("zwin");

pub fn main() !void {
    const file_name = "fmtest.txt";
    var example_mmap = try zwin.FileMapped.init(file_name);
    defer example_mmap.deinit();

    inline for (std.meta.fields(@TypeOf(example_mmap.sys_info))) |f| {
        std.log.debug(f.name ++ " {any}", .{@as(f.type, @field(example_mmap.sys_info, f.name))});
    }

    std.debug.print("file: {s}, mmap size: {d}\n", .{file_name, example_mmap.size()});
}
