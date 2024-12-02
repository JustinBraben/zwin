const std = @import("std");
const zwin = @import("zwin");
const win32 = @import("zigwin32").everything;

const CityStats = struct {
    min: f64,
    max: f64,
    sum: f64,
    count: u64,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Get and print them!
    std.debug.print("There are {d} args:\n", .{args.len});
    for(args) |arg| {
        std.debug.print("  {s}\n", .{arg});
    }

    if (args.len != 2) {
        std.debug.print("Must pass measurements.txt as first positional.\n", .{});
        return error.NoInputFile;
    }

    const file_name = args[1][0..];
    const file_handle = win32.CreateFileA(
        file_name, 
        win32.FILE_READ_DATA,
        win32.FILE_SHARE_READ, 
        null, 
        win32.OPEN_EXISTING, 
        win32.FILE_ATTRIBUTE_NORMAL, 
        null
    );
    defer _ = win32.CloseHandle(file_handle);

    // Check for file handle error
    if (file_handle == win32.INVALID_HANDLE_VALUE) {
        const error_code = win32.GetLastError();
        std.debug.print("Failed to open file. Error code: {}\n", .{error_code});
        return error.FileOpenFailed;
    }

    // Get file size
    var file_size: win32.LARGE_INTEGER = undefined;
    if (win32.GetFileSizeEx(file_handle, &file_size) == 0) {
        const error_code = win32.GetLastError();
        std.debug.print("Failed to get file size. Error code: {}\n", .{error_code});
        return error.FileSizeFailed;
    }

    // Use QuadPart to get the full 64-bit file size
    std.debug.print("{s} size: {} bytes\n", .{file_name, file_size.QuadPart});

    // Create file mapping
    const mapping_handle = win32.CreateFileMappingA(
        file_handle,
        null,
        win32.PAGE_READONLY,
        @intCast(file_size.QuadPart >> 32),  // High 32 bits of file size
        @intCast(file_size.QuadPart & 0xFFFFFFFF),  // Low 32 bits of file size
        null
    );
    defer _ = win32.CloseHandle(mapping_handle);

    // Map view of file
    const mapped_view = win32.MapViewOfFile(
        mapping_handle,
        win32.FILE_MAP_READ,
        0,
        0,
        0  // Map entire file
    );
    defer _ = win32.UnmapViewOfFile(mapped_view);

    // Must be usize for slice [0..x]
    const slice_size: usize = @intCast(file_size.QuadPart);

    // Convert mapped view to slice and print first line
    const file_contents = @as([*]const u8, @ptrCast(mapped_view))[0..slice_size];

    // Create a hash map to store city statistics
    var city_stats = std.StringHashMap(CityStats).init(allocator);
    defer city_stats.deinit();

    // Process each line
    var lines = std.mem.split(u8, file_contents, "\n");
    std.debug.print("Line 1: {?s}\n", .{lines.next()});
    std.debug.print("Line 2: {?s}\n", .{lines.next()});

    // while (lines.next()) |line| {
    //     // Skip empty lines
    //     if (line.len == 0) continue;
    // }

    // // Print results
    // var city_iterator = city_stats.iterator();
    // while (city_iterator.next()) |entry| {
    //     const city = entry.key_ptr.*;
    //     const stats = entry.value_ptr.*;
    //     const avg = stats.sum / @as(f64, @floatFromInt(stats.count));
        
    //     std.debug.print("{s}={d:.1}/{d:.1}/{d:.1}\n", .{
    //         city, 
    //         stats.min, 
    //         avg, 
    //         stats.max
    //     });
    // }
}