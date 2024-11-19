const std = @import("std");
const WINAPI = std.os.windows.WINAPI;
const win32 = @import("zigwin32").everything;

const FileMapped = @This();

handle: win32.HANDLE,
sys_info: win32.SYSTEM_INFO = undefined,

pub fn init(file: [*:0]const u8) !FileMapped {
    const handle = win32.CreateFileA(file, .{ .FILE_READ_DATA = 1, .FILE_WRITE_DATA = 1 }, win32.FILE_SHARE_READ, null, .CREATE_ALWAYS, .{ .FILE_ATTRIBUTE_NORMAL = 1 }, null);

    // Get sys info for memory mapped file
    var sys_info: win32.SYSTEM_INFO = undefined;
    win32.GetSystemInfo(&sys_info);

    return .{
        .handle = handle,
        .sys_info = sys_info,
    };
}

pub fn deinit(self: *FileMapped) void {
    _ = win32.CloseHandle(self.handle);
}

pub fn size(self: *FileMapped) u32 {
    return win32.GetFileSize(self.handle, null);
}

pub fn GetSysInfo(self: *FileMapped) void {
    win32.GetSystemInfo(&self.sys_info);
}

// pub fn run(self: *FileMapped) !void {
//     _ = &self;
// }
