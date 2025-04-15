//! file_mapped.zig
//! Memory mapped file abstraction for easier file access in Win32

const std = @import("std");
const testing = std.testing;
const windows = std.os.windows;
const WINAPI = std.os.windows.WINAPI;
const win32 = @import("win32").everything;

/// Errors that can occur when working with memory mapped files
pub const FileMapError = error{
    InvalidHandle,
    MapFileNull,
    MapViewNull,
    ResizeFailed,
    AccessDenied,
    InvalidSize,
};

/// Access modes for memory mapped files
pub const FileAccess = enum {
    read_only,
    read_write,
};

/// Configuration options for creating a memory mapped file
pub const CreateOptions = struct {
    /// Size of the buffer to map
    buff_size: u32 = 1024,
    /// Offset from the beginning of the file to start mapping
    file_map_start: u32 = 0,
    /// File creation disposition (CREATE_ALWAYS, OPEN_EXISTING, etc.)
    creation_disposition: win32.FILE_CREATION_DISPOSITION = .CREATE_ALWAYS,
    /// Access type (read_only or read_write)
    access_type: FileAccess = .read_write,
};

/// FileMapped provides a memory-mapped file abstraction
const FileMapped = @This();

// File handles and mapping objects
handle: win32.HANDLE = windows.INVALID_HANDLE_VALUE,
map_handle: ?win32.HANDLE = null,
map_address: ?windows.LPVOID = null,
access_type: FileAccess,
file_path: [:0]const u8,
allocator: std.mem.Allocator,

// System information
sys_info: win32.SYSTEM_INFO = undefined,
sys_granularity: u32,

// Mapping configuration
map_start: u32,
map_size: u32,
view_size: u32,
view_delta: u32,
buff_size: u32,

/// Initialize a memory mapped file with the given options
pub fn init(allocator: std.mem.Allocator, file_path: []const u8, options: CreateOptions) !*FileMapped {
    // Create a null-terminated copy of the file path
    const path_copy = try allocator.dupeZ(u8, file_path);
    errdefer allocator.free(path_copy);
    
    // Create the FileMapped instance
    const file_mapped = try allocator.create(FileMapped);
    errdefer allocator.destroy(file_mapped);

    const access_flags: win32.FILE_ACCESS_FLAGS = switch (options.access_type) {
        .read_only => .{ .FILE_READ_DATA = 1 },
        .read_write => .{ .FILE_READ_DATA = 1, .FILE_WRITE_DATA = 1 },
    };

    // Open the file
    const handle = win32.CreateFileA(
        path_copy, 
        access_flags,
        .{ .READ = 1, .WRITE = 1 }, 
        null, 
        options.creation_disposition, 
        .{ .FILE_ATTRIBUTE_NORMAL = 1 }, 
        null
    );

    // Check if file handle is valid
    if (handle == std.os.windows.INVALID_HANDLE_VALUE) {
        return FileMapError.InvalidHandle;
    }

    // Get sys info for memory mapped file
    var sys_info: win32.SYSTEM_INFO = undefined;
    win32.GetSystemInfo(&sys_info);
    const sys_granularity = sys_info.dwAllocationGranularity;

    // Calculate mapping parameters
    const map_start = (options.file_map_start / sys_granularity) * sys_granularity;
    const view_size = (options.file_map_start % sys_granularity) + options.buff_size;
    const map_size = options.file_map_start + options.buff_size;
    const view_delta = options.file_map_start - map_start;

    // Initialize the FileMapped struct
    file_mapped.* = .{
        .handle = handle,
        .access_type = options.access_type,
        .sys_info = sys_info,
        .sys_granularity = sys_granularity,
        .map_start = map_start,
        .map_size = map_size,
        .view_size = view_size,
        .view_delta = view_delta,
        .buff_size = options.buff_size,
        .file_path = path_copy,
        .allocator = allocator,
        .map_handle = null,
        .map_address = null,
    };

    // Immediately create the mapping and map the view for easier use
    file_mapped.createMapping() catch |err| {
        file_mapped.deinit();
        return err;
    };
    
    file_mapped.mapView() catch |err| {
        file_mapped.deinit();
        return err;
    };

    return file_mapped;
}

/// Clean up all resources associated with the memory mapped file
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

    self.allocator.free(self.file_path);
    self.allocator.destroy(self);
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

/// Get a pointer to the mapped data
pub fn getData(self: *FileMapped) ![]u8 {
    if (self.map_address) |addr| {
        const data_ptr: [*]u8 = @ptrFromInt(@intFromPtr(addr) + self.view_delta);
        return data_ptr[0..self.buff_size];
    }
    return FileMapError.MapViewNull;
}

/// Get a typed pointer to the mapped data
pub fn getDataAs(self: *FileMapped, comptime T: type) ![]T {
    if (self.map_address) |addr| {
        const data_ptr: [*]u8 = @ptrFromInt(@intFromPtr(addr) + self.view_delta);
        
        // Check alignment requirements
        const alignment = @alignOf(T);
        const ptr_addr = @intFromPtr(data_ptr);
        if (ptr_addr % alignment != 0) {
            // Handle unaligned access by returning an error
            return FileMapError.AccessDenied;
        }
        
        // Calculate how many complete T elements fit in the buffer
        const count = self.buff_size / @sizeOf(T);
        if (count == 0) return FileMapError.InvalidSize;
        
        const typed_ptr: [*]T = @ptrCast(@alignCast(data_ptr));
        return typed_ptr[0..count];
    }
    return FileMapError.MapViewNull;
}

/// Get the size of the mapped file
pub fn size(self: *FileMapped) u32 {
    return win32.GetFileSize(self.handle, null);
}

/// Flush changes to disk
pub fn flush(self: *FileMapped) bool {
    if (self.map_address) |addr| {
        return win32.FlushViewOfFile(addr, 0) != 0;
    }
    return false;
}

/// Set the size of the file and remap it
pub fn resize(self: *FileMapped, new_size: u32) !void {
    // Only allow resize in read_write mode
    if (self.access_type != .read_write) {
        return FileMapError.AccessDenied;
    }
    
    // Unmap existing view
    if (self.map_address != null) {
        _ = win32.UnmapViewOfFile(self.map_address);
        self.map_address = null;
    }
    
    // Close existing mapping
    if (self.map_handle != null) {
        _ = win32.CloseHandle(self.map_handle);
        self.map_handle = null;
    }
    
    // Move file pointer to desired size
    if (win32.SetFilePointer(self.handle, @intCast(new_size), null, win32.FILE_BEGIN) == 0xFFFFFFFF) {
        return FileMapError.ResizeFailed;
    }
    
    // Set end of file at current position
    if (win32.SetEndOfFile(self.handle) == 0) {
        return FileMapError.ResizeFailed;
    }
    
    // Update size information
    self.buff_size = new_size;
    self.map_size = self.map_start + new_size;
    self.view_size = (self.map_start % self.sys_granularity) + new_size;
    
    // Recreate mapping and view
    try self.createMapping();
    try self.mapView();
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
    const allocator = testing.allocator;
    
    const file_name = "test_init.txt";
    var mapped_file = try FileMapped.init(allocator, file_name, .{});
    defer mapped_file.deinit();
    
    try testing.expect(mapped_file.handle != std.os.windows.INVALID_HANDLE_VALUE);
    try testing.expect(mapped_file.map_handle != null);
    try testing.expect(mapped_file.map_address != null);
}

test "FileMapped write and read data" {
    const allocator = testing.allocator;

    const file_name = "test_write_read.txt";
    
    // Create test data
    const test_data = "Hello, Memory Mapped World!";
    
    {
        const file = try std.fs.cwd().createFile(file_name, .{});
        defer file.close();
        try file.writeAll(test_data);
    }
    
    // Map the file
    var mapped_file = try FileMapped.init(allocator, file_name, .{
        .buff_size = @intCast(test_data.len),
        .file_map_start = 0,
        .creation_disposition = .OPEN_EXISTING
    });
    defer mapped_file.deinit();
    
    // Read and verify data
    const mapped_data = try mapped_file.getData();
    try testing.expectEqualStrings(test_data, mapped_data);
    
    // Test typed access for a simple case (array of bytes)
    const typed_data = try mapped_file.getDataAs(u8);
    try testing.expectEqualStrings(test_data, typed_data);
}

test "FileMapped typed access" {
    const allocator = testing.allocator;
    
    const file_name = "test_typed_access.txt";
    
    // Create a file with some u32 values
    const TestStruct = struct {
        a: u32,
        b: u32,
        c: u32,
    };
    
    const test_struct = TestStruct{ .a = 123, .b = 456, .c = 789 };
    
    {
        const file = try std.fs.cwd().createFile(file_name, .{});
        defer file.close();
        try file.writeAll(std.mem.asBytes(&test_struct));
    }
    
    // Map the file with typed access
    var mapped_file = try FileMapped.init(allocator, file_name, .{
        .buff_size = @sizeOf(TestStruct),
        .file_map_start = 0,
        .creation_disposition = .OPEN_EXISTING
    });
    defer mapped_file.deinit();
    
    // Access as TestStruct
    const struct_data = (try mapped_file.getDataAs(TestStruct))[0];
    try testing.expectEqual(test_struct.a, struct_data.a);
    try testing.expectEqual(test_struct.b, struct_data.b);
    try testing.expectEqual(test_struct.c, struct_data.c);
}

test "FileMapped resize" {
    const allocator = testing.allocator;
    
    const file_name = "test_resize.txt";
    
    var mapped_file = try FileMapped.init(allocator, file_name, .{
        .buff_size = 100,
    });
    defer mapped_file.deinit();
    
    // Write some data
    var data = try mapped_file.getData();
    @memset(data, 'A');
    
    // Flush to disk
    _ = mapped_file.flush();
    
    // Resize to larger size
    try mapped_file.resize(200);
    
    // Verify size
    try testing.expectEqual(@as(u32, 200), mapped_file.buff_size);
    
    // Write to the extended area
    data = try mapped_file.getData();
    try testing.expectEqual(@as(usize, 200), data.len);
    
    // First 100 bytes should still be 'A'
    for (0..100) |i| {
        try testing.expectEqual(@as(u8, 'A'), data[i]);
    }
    
    // Fill remaining with 'B'
    for (100..200) |i| {
        data[i] = 'B';
    }
    
    // Flush changes
    _ = mapped_file.flush();
    
    // Resize to smaller size
    try mapped_file.resize(50);
    try testing.expectEqual(@as(u32, 50), mapped_file.buff_size);
    
    // Data should be truncated
    data = try mapped_file.getData();
    try testing.expectEqual(@as(usize, 50), data.len);
    
    // All bytes should still be 'A'
    for (0..50) |i| {
        try testing.expectEqual(@as(u8, 'A'), data[i]);
    }
}

test "FileMapped error handling" {
    const allocator = testing.allocator;
    
    // Test invalid file
    try testing.expectError(
        FileMapError.InvalidHandle,
        FileMapped.init(allocator, "nonexistent_file.txt", .{
            .creation_disposition = .OPEN_EXISTING,
        })
    );
}

// Clean up test files when tests complete
test {
    defer {
        std.fs.cwd().deleteFile("test_init.txt") catch {};
        std.fs.cwd().deleteFile("test_write_read.txt") catch {};
        std.fs.cwd().deleteFile("test_typed_access.txt") catch {};
        std.fs.cwd().deleteFile("test_resize.txt") catch {};
    }
}