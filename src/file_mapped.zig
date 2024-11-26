const std = @import("std");
const testing = std.testing;
const windows = std.os.windows;
const WINAPI = std.os.windows.WINAPI;
const win32 = @import("zigwin32").everything;

pub const FileMapError = error{
    InvalidHandle,
    MapFileNull,
    MapViewNull,
    ResizeFailed,
    AccessDenied,
};

pub const FileAccess = enum {
    read_only,
    read_write,
};

pub const FileMappedConfig = struct {
    buff_size: u32 = 1024,
    file_map_start: u32 = 0,
    creation_disposition: win32.FILE_CREATION_DISPOSITION = .CREATE_ALWAYS,
    access_type: FileAccess = .read_write,
};

const FileMapped = @This();

// File handles and mapping objects
handle: win32.HANDLE = windows.INVALID_HANDLE_VALUE,
map_handle: ?win32.HANDLE = null,
map_address: ?windows.LPVOID = null,
access_type: FileAccess,

// System information
sys_info: win32.SYSTEM_INFO = undefined,
sys_granularity: u32,

// Mapping configuration
map_start: u32,
map_size: u32,
view_size: u32,
view_delta: u32,
buff_size: u32,

pub fn init(file: [*:0]const u8, config: FileMappedConfig) FileMapError!FileMapped {
    const access_flags: win32.FILE_ACCESS_FLAGS = switch (config.access_type) {
        .read_only => .{ .FILE_READ_DATA = 1 },
        .read_write => .{ .FILE_READ_DATA = 1, .FILE_WRITE_DATA = 1 },
    };

    const handle = win32.CreateFileA(
        file, 
        access_flags,
        win32.FILE_SHARE_READ, 
        null, 
        config.creation_disposition, 
        .{ .FILE_ATTRIBUTE_NORMAL = 1 }, 
        null);

    if (handle == std.os.windows.INVALID_HANDLE_VALUE) {
        return FileMapError.InvalidHandle;
    }

    // Get sys info for memory mapped file
    var sys_info: win32.SYSTEM_INFO = undefined;
    win32.GetSystemInfo(&sys_info);
    const sys_granularity = sys_info.dwAllocationGranularity;

    // Calculate mapping parameters
    const map_start = (config.file_map_start / sys_granularity) * sys_granularity;
    const view_size = (config.file_map_start % sys_granularity) + config.buff_size;
    const map_size = config.file_map_start + config.buff_size;
    const view_delta = config.file_map_start - map_start;

    return .{
        .handle = handle,
        .access_type = config.access_type,
        .sys_info = sys_info,
        .sys_granularity = sys_granularity,
        .map_start = map_start,
        .map_size = map_size,
        .view_size = view_size,
        .view_delta = view_delta,
        .buff_size = config.buff_size,
    };
}

pub fn deinit(self: *FileMapped) void {
    if (self.map_address) |addr| {
        _ = win32.UnmapViewOfFile(addr);
        self.map_address = null;
    }
    
    if (self.map_handle) |handle| {
        _ = win32.CloseHandle(handle);
        self.map_handle = null;
    }

    if (self.handle != windows.INVALID_HANDLE_VALUE) {
        _ = win32.CloseHandle(self.handle);
        self.handle = windows.INVALID_HANDLE_VALUE;
    }
}

pub fn createMapping(self: *FileMapped) !void {
    self.map_handle = win32.CreateFileMappingA(
        self.handle,
        null,
        switch (self.access_type) {
            .read_only => .{ .PAGE_READONLY = 1 },
            .read_write => .{ .PAGE_READWRITE = 1 },
        },
        0,
        self.map_size,
        null
    );

    if (self.map_handle == null) {
        return FileMapError.MapFileNull;
    }
}

pub fn mapView(self: *FileMapped) !void {
    self.map_address = win32.MapViewOfFile(
        self.map_handle,
        switch (self.access_type) {
                .read_only => win32.FILE_MAP_READ,
                .read_write => win32.FILE_MAP_ALL_ACCESS,
        },
        0,
        self.map_start,
        self.view_size
    );

    if (self.map_address == null) {
        return FileMapError.MapViewNull;
    }
}

pub fn getDataPointer(self: *FileMapped) !*u32 {
    if (self.map_address) |addr| {
        const data_ptr: *u8 = @ptrFromInt(@intFromPtr(addr) + self.view_delta);
        return @ptrCast(@alignCast(data_ptr));
    }
    return FileMapError.MapViewNull;
}

pub fn size(self: *FileMapped) u32 {
    return win32.GetFileSize(self.handle, null);
}

pub fn GetSysInfo(self: *FileMapped) void {
    win32.GetSystemInfo(&self.sys_info);
}

pub fn dump(self: *FileMapped) void {
    // Print file map view info
    std.log.debug("The file map view starts at {d} bytes into the file.\n", .{self.map_start});
    std.log.debug("The file map view is {d} bytes large.\n", .{self.view_size});
    std.log.debug("The file mapping object is {d} bytes large.\n", .{self.map_size});
    std.log.debug("The data is {d} bytes into the view.\n", .{self.view_delta});

    // Print self.sys_info
    inline for (std.meta.fields(@TypeOf(self.sys_info))) |f| {
        std.log.debug(f.name ++ " {any}", .{@as(f.type, @field(self.sys_info, f.name))});
    }
}

test "FileMapped basic initialization" {
    const file_name = "test_init.txt";
    var mapped_file = try FileMapped.init(file_name, .{});
    defer mapped_file.deinit();
    
    try testing.expect(mapped_file.handle != std.os.windows.INVALID_HANDLE_VALUE);
    try testing.expect(mapped_file.map_handle == null);
    try testing.expect(mapped_file.map_address == null);
}

test "FileMapped write and read data" {
    const file_name = "test_write_read.txt";
    
    // Create test data
    const test_data = "Hello, Memory Mapped World!";
    
    {
        const file = try std.fs.cwd().createFile(file_name, .{});
        defer file.close();
        try file.writeAll(test_data);
    }
    
    // Map the file
    var mapped_file = try FileMapped.init(file_name, .{
        .buff_size = test_data.len,
        .file_map_start = 0,
        .creation_disposition = .OPEN_EXISTING
    });
    defer mapped_file.deinit();
    
    try mapped_file.createMapping();
    try mapped_file.mapView();
    
    // Read and verify data
    const data_ptr = try mapped_file.getDataPointer();
    const mapped_data = @as([*]u8, @ptrCast(data_ptr))[0..test_data.len];
    try testing.expectEqualStrings(test_data, mapped_data);
}

test "FileMapped error handling" {
    // Test invalid file
    try testing.expectError(
        FileMapError.InvalidHandle,
        FileMapped.init("nonexistent_file.txt", .{
            .creation_disposition = .OPEN_EXISTING,
        })
    );
    
    // Test mapping without creating file
    const file_name = "test_errors.txt";
    var mapped_file = try FileMapped.init(file_name, .{});
    defer mapped_file.deinit();
    
    // Try to map view without creating mapping first
    try testing.expectError(error.MapViewNull, mapped_file.mapView());
}

// Helper function to clean up test files
fn cleanupTestFiles() void {
    std.fs.cwd().deleteFile("test_init.txt") catch {};
    std.fs.cwd().deleteFile("test_write_read.txt") catch {};
    std.fs.cwd().deleteFile("test_size.txt") catch {};
    std.fs.cwd().deleteFile("test_errors.txt") catch {};
    std.fs.cwd().deleteFile("test_full_map.txt") catch {};
}