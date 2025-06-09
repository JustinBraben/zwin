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
    PathTooLong,
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

// Store path directly in struct with fixed buffer
file_path: [260:0]u8 = std.mem.zeroes([260:0]u8), // MAX_PATH on Windows
file_path_len: u16 = 0,

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
pub fn init(file_path: []const u8, options: CreateOptions) !FileMapped {
    // Check path length
    if (file_path.len >= 260) {
        return FileMapError.PathTooLong;
    }
    
    var file_mapped = FileMapped{
        .access_type = options.access_type,
        .sys_granularity = undefined,
        .map_start = undefined,
        .map_size = undefined,
        .view_size = undefined,
        .view_delta = undefined,
        .buff_size = options.buff_size,
    };
    
    // Copy path and null terminate
    @memcpy(file_mapped.file_path[0..file_path.len], file_path);
    file_mapped.file_path[file_path.len] = 0;
    file_mapped.file_path_len = @intCast(file_path.len);

    const access_flags: win32.FILE_ACCESS_FLAGS = switch (options.access_type) {
        .read_only => .{ .FILE_READ_DATA = 1 },
        .read_write => .{ .FILE_READ_DATA = 1, .FILE_WRITE_DATA = 1 },
    };

    // Open the file
    file_mapped.handle = win32.CreateFileA(
        @ptrCast(&file_mapped.file_path), 
        access_flags,
        .{ .READ = 1, .WRITE = 1 }, 
        null, 
        options.creation_disposition, 
        .{ .FILE_ATTRIBUTE_NORMAL = 1 }, 
        null
    );

    // Check if file handle is valid
    if (file_mapped.handle == std.os.windows.INVALID_HANDLE_VALUE) {
        return FileMapError.InvalidHandle;
    }

    // Get sys info for memory mapped file
    win32.GetSystemInfo(&file_mapped.sys_info);
    file_mapped.sys_granularity = file_mapped.sys_info.dwAllocationGranularity;

    // Calculate mapping parameters
    file_mapped.map_start = (options.file_map_start / file_mapped.sys_granularity) * file_mapped.sys_granularity;
    file_mapped.view_size = (options.file_map_start % file_mapped.sys_granularity) + options.buff_size;
    file_mapped.map_size = options.file_map_start + options.buff_size;
    file_mapped.view_delta = options.file_map_start - file_mapped.map_start;

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

/// Get the stored file path
pub fn getFilePath(self: *const FileMapped) []const u8 {
    return self.file_path[0..self.file_path_len];
}


// Updated tests for allocator-free version
test "FileMapped basic initialization" {
    const file_name = "test_init.txt";
    var mapped_file = try FileMapped.init(file_name, .{});
    defer mapped_file.deinit();
    
    try testing.expect(mapped_file.handle != std.os.windows.INVALID_HANDLE_VALUE);
    try testing.expect(mapped_file.map_handle != null);
    try testing.expect(mapped_file.map_address != null);
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

test "FileMapped path too long" {
    const long_path = "a" ** 300; // Exceeds MAX_PATH
    try testing.expectError(
        FileMapError.PathTooLong,
        FileMapped.init(long_path, .{})
    );
}

test "FileMapped error handling" {
    // Test invalid file
    try testing.expectError(
        FileMapError.InvalidHandle,
        FileMapped.init("nonexistent_file.txt", .{
            .creation_disposition = .OPEN_EXISTING,
        })
    );
}

// Clean up test files when tests complete
test {
    defer {
        std.fs.cwd().deleteFile("test_init.txt") catch {};
        std.fs.cwd().deleteFile("test_write_read.txt") catch {};
    }
}