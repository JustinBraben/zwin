const std = @import("std");
const WINAPI = std.os.windows.WINAPI;
const win32 = @import("zigwin32").everything;

const Window = @This();

instance: win32.HINSTANCE,
class: win32.WNDCLASSA,
handle: ?win32.HWND = null,

pub fn init(class_name: [*:0]const u8, menu_name: [*:0]const u8) !Window {
    return .{
        .instance = win32.GetModuleHandleA(null) orelse return error.InstanceNull,
        .class = .{
            .style = .{},
            .lpfnWndProc = WindowProc,
            .cbClsExtra = 0,
            .cbWndExtra = 0,
            .hInstance = win32.GetModuleHandleA(null) orelse return error.InstanceNull,
            .hIcon = null,
            .hCursor = null,
            .hbrBackground = null,
            .lpszMenuName = menu_name,
            .lpszClassName = class_name,
        },
        .handle = null,
    };
}

pub fn deinit(self: *Window) void {
    _ = &self;
}

pub fn run(self: *Window) !void {
    // returning 0 means RegisterClassA failed
    if (win32.RegisterClassA(&self.class) == 0) {
        std.debug.panic("RegisterClass failed with {}", .{win32.GetLastError().fmt()});
    }

    self.handle = win32.CreateWindowExA(.{}, self.class.lpszClassName, "Learn to Program Windows", win32.WS_OVERLAPPEDWINDOW, win32.CW_USEDEFAULT, win32.CW_USEDEFAULT, win32.CW_USEDEFAULT, win32.CW_USEDEFAULT, null, null, self.instance, null) orelse return error.HandleNull;

    _ = win32.ShowWindow(self.handle, .{ .SHOWNORMAL = 1 });

    var msg: win32.MSG = undefined;
    while (win32.GetMessageW(&msg, null, 0, 0) != 0) {
        _ = win32.TranslateMessage(&msg);
        _ = win32.DispatchMessageW(&msg);
    }
}

fn WindowProc(hWnd: win32.HWND, Msg: u32, wParam: win32.WPARAM, lParam: win32.LPARAM) callconv(WINAPI) win32.LRESULT {
    switch (Msg) {
        win32.WM_DESTROY => {
            win32.PostQuitMessage(0);
            return 0;
        },
        win32.WM_PAINT => {
            var ps: win32.PAINTSTRUCT = undefined;
            const hdc = win32.BeginPaint(hWnd, &ps);
            _ = win32.FillRect(hdc, &ps.rcPaint, @ptrFromInt(@intFromEnum(win32.COLOR_WINDOW) + 1));

            _ = win32.EndPaint(hWnd, &ps);
            return 0;
        },
        else => {},
    }
    return win32.DefWindowProcA(hWnd, Msg, wParam, lParam);
}
