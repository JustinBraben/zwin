const std = @import("std");
const windows = std.os.windows;

pub fn main() !void {
    std.debug.print("Hello\n", .{});

    var hFile = try std.fs.cwd().openFile("fmtest.txt", .{ .mode = .read_only});
    defer hFile.close();

    // var FileSize: windows.DWORD = undefined;
    // windows.GetFileSizeEx(hFile.handle);

    // const file_size = (try hFile.stat()).size;
    var file_size: i64 = @intCast(try windows.GetFileSizeEx(hFile.handle));
    if (file_size == 0) {
        std.debug.print("file_size is 0, exiting...\n", .{});
        return error.FileSizeZero;
    }

    const hModule = windows.kernel32.GetModuleHandleW(null) orelse {
        std.debug.print("hModule is null, exiting...\n", .{});
        return error.ModuleHandleNull;
    };

    var SectionHandle: windows.HANDLE = undefined;
    const section_status = windows.ntdll.NtCreateSection(
        &SectionHandle, 
        windows.SECTION_MAP_READ | windows.SECTION_MAP_WRITE, 
        null, 
        &file_size, 
        windows.PAGE_READWRITE, 
        windows.SEC_COMMIT, 
        null);

    var address: windows.PVOID = undefined;
    var section_size: windows.SIZE_T = 0;
    const map_view_of_section_status = windows.ntdll.NtMapViewOfSection(
        SectionHandle, 
        windows.GetCurrentProcess(), 
        &address, 
        null, 
        0, 
        null, 
        &section_size, 
        .ViewUnmap, 
        windows.MEM_COMMIT, 
        windows.PAGE_READWRITE);

    _ = hModule;
    _ = section_status;
    _ = map_view_of_section_status;
}
