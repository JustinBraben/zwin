const std = @import("std");
const windows = std.os.windows;
const win32 = @import("zigwin32");
const foundation = win32.foundation;
const system = win32.system;
const system_information = system.system_information;
const memory = system.memory;
const file_system = win32.storage.file_system;
const win32_zig = win32.zig;

pub const UNICODE = true;

/// Size of the memory to examine at any one time
const BUFFSIZE = 1024;

/// Starting point within the file of
/// the data to examine (135K)
const FILE_MAP_START = 138240;

pub fn main() !void {
    const stdout_file = std.io.getStdOut().writer();
    const stderr_file = std.io.getStdErr().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    var bw_err = std.io.bufferedWriter(stderr_file);
    const stdout = bw.writer();
    const stderr = bw_err.writer();

    // Handle for the file's memory-mapped region
    var hMapFile: ?HANDLE = undefined;
    // the file handle
    var hFile: HANDLE = undefined;
    // number of bytes written
    var dBytesWritten: DWORD = undefined;
    // temporary storage for file sizes
    var dwFileSize: DWORD = undefined;
    // size of the file mapping
    var dwFileMapSize: DWORD = undefined;
    // the size of the view
    var dwMapViewSize: DWORD = undefined;
    // where to start the file map view
    var dwFileMapStart: DWORD = undefined;
    // system allocation granularity
    var dwSysGran: DWORD = undefined;
    // system information; used to get granularity
    var SysInfo: SYSTEM_INFO = undefined;
    // pointer to the base address of the memory-mapped region
    var lpMapAddress: ?LPVOID = undefined;

    var pData: *u8 = undefined; // pointer to the data

    var iData: *u32 = undefined; // on success contains the first int of data
    var iViewDelta: DWORD = undefined; // the offset into the view where the data shows up

    const file_name = "fmtest.txt";
    const dir = std.fs.cwd();
    const path_w = try windows.sliceToPrefixedFileW(dir.fd, file_name);
    const lpcTheFile = path_w.span(); // the file to be manipulated
    try stdout.print("typeOf(lpcTheFile): {s}\n", .{@typeName(@TypeOf(lpcTheFile))});
    hFile = file_system.CreateFileW(
        lpcTheFile, 
        .{.FILE_READ_DATA = 1, .FILE_WRITE_DATA = 1}, 
        file_system.FILE_SHARE_READ, 
        null, 
        .CREATE_ALWAYS, 
        file_system.FILE_ATTRIBUTE_NORMAL, 
        null);
    defer _ = win32_zig.closeHandle(hFile); // close the file mapping object

    if (hFile == windows.INVALID_HANDLE_VALUE) {
        try stderr.print("hFile is NULL\n", .{});
        try stderr.print("Target file is {s}\n", .{file_name});
        return error.INVALID_HANDLE_VALUE;
    }

    // Get the system allocation granularity.
    system_information.GetSystemInfo(&SysInfo);
    dwSysGran = SysInfo.dwAllocationGranularity;

    // Now calculate a few variables. Calculate the file offsets as
    // 64-bit values, and then get the low-order 32 bits for the
    // function calls.
    // To calculate where to start the file mapping, round down the
    // offset of the data into the file to the nearest multiple of the
    // system allocation granularity.
    dwFileMapStart = (FILE_MAP_START / dwSysGran) * dwSysGran;
    try stdout.print("The file map view starts at {d} bytes into the file.\n", .{dwFileMapStart});

    // Calculate the size of the file mapping view.
    dwMapViewSize = (FILE_MAP_START % dwSysGran) + BUFFSIZE;
    try stdout.print("The file map view is {d} bytes large.\n", .{dwMapViewSize});

    // How large will the file mapping object be?
    dwFileMapSize = FILE_MAP_START + BUFFSIZE;
    try stdout.print("The file mapping object is {d} bytes large.\n", .{dwFileMapSize});

    // The data of interest isn't at the beginning of the
    // view, so determine how far into the view to set the pointer.
    iViewDelta = FILE_MAP_START - dwFileMapStart;
    try stdout.print("The data is {d} bytes into the view.\n", .{iViewDelta});

    // Now write a file with data suitable for experimentation. This
    // provides unique int (4-byte) offsets in the file for easy visual
    // inspection. Note that this code does not check for storage
    // medium overflow or other errors, which production code should
    // do. Because an int is 4 bytes, the value at the pointer to the
    // data should be one quarter of the desired offset into the file

    var i: u32 = 0;
    while (i < dwSysGran) : (i += 1) {
        _ = win32.storage.file_system.WriteFile(hFile, &i, @intCast(@sizeOf(@TypeOf(i))), &dBytesWritten, null);
    }

    // Verify that the correct file size was written.
    dwFileSize = win32.storage.file_system.GetFileSize(hFile, null);
    try stdout.print("hFile size: {d}\n", .{dwFileSize});

    // Create a file mapping object for the file
    // Note that it is a good idea to ensure the file size is not zero
    hMapFile = memory.CreateFileMapping(hFile, // current file handle
        null, // default security
        .{ .PAGE_READWRITE = 1 }, // read/write permission
        0, // size of mapping object, high
        dwFileMapSize, // size of mapping object, low
        null); // name of mapping object
    defer {
        if (hMapFile) |map_file| _ = win32_zig.closeHandle(map_file); // close the file mapping object
    }

    if (hMapFile == null) {
        try stderr.print("hMapFile is NULL: last error: {}\n", .{foundation.GetLastError()});
        return error.hMapFileIsNull;
    }

    // Map the view and test the results.
    lpMapAddress = memory.MapViewOfFile(hMapFile, //handle to mapping object
        memory.FILE_MAP_ALL_ACCESS, // read/write high-order 32
        0, dwFileMapStart, dwMapViewSize);
    defer {
        if (lpMapAddress) |map_address| _ = memory.UnmapViewOfFile(map_address);
    }

    if (lpMapAddress == null) {
        try stderr.print("lpMapAddress is NULL: last error: {d}\n", .{foundation.GetLastError()});
        return error.lpMapAddressFileIsNull;
    }

    pData = @ptrFromInt(@intFromPtr(lpMapAddress.?) + iViewDelta);
    iData = @ptrCast(@alignCast(pData));

    try stdout.print("The value at the pointer is {d},\nwhich {s} one quarter of the desired file offset.\n", .{
        iData.*,
        if (iData.* * 4 == FILE_MAP_START) "is" else "is not",
    });

    try bw.flush(); // don't forget to flush!
}

const SYSTEM_INFO = system_information.SYSTEM_INFO;
const HANDLE = windows.HANDLE;
const BOOL = windows.DWORD;
const DWORD = windows.DWORD;
const INT = windows.INT;
const LPVOID = windows.LPVOID;
