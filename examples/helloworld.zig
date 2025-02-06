const win32 = @import("win32").everything;
const std = @import("std");

pub const UNICODE = true;
pub fn main() !void {
    const hStdOut = win32.GetStdHandle(win32.STD_OUTPUT_HANDLE);
    if (hStdOut == win32.INVALID_HANDLE_VALUE) {
        win32.ExitProcess(255);
    }

    const res = writeAll(hStdOut, "Hello, World!");

    if (res) |r| {
        if (r != .NO_ERROR) try std.io.getStdErr().writer().print("err: {}", .{r});
    }

    // Success
    win32.ExitProcess(0);
}

fn writeAll(hFile: win32.HANDLE, buffer: []const u8) ?win32.WIN32_ERROR {
    var written: usize = 0;
    while (written < buffer.len) {
        const next_write = @as(u32, @intCast(0xFFFFFFFF & (buffer.len - written)));
        var last_written: u32 = undefined;
        if (1 != win32.WriteFile(hFile, buffer.ptr + written, next_write, &last_written, null)) {
            // try std.io.getStdErr().writer().print("err: {any}", .{win32.GetLastError()});
            return win32.GetLastError();
        }
        written += last_written;
    }
    return null;
}
