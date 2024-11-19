const std = @import("std");
const WINAPI = std.os.windows.WINAPI;
const win32 = @import("zigwin32").everything;

pub fn main() !void {
    var hInstance: win32.HINSTANCE = undefined;
    hInstance = win32.GetModuleHandleA(null) orelse {
        std.debug.print("GetModuleHandleA returned null, exiting\n", .{});
        return;
    };

    // var WindowProc: win32.WNDPROC = undefined;
    // WindowProc = win32.DefWindowProcA;

    const CLASS_NAME = "Sample Window Class";
    const MENU_NAME = "Sample Window Menu";
    var wc: win32.WNDCLASSA = undefined;
    wc = .{
        .style = .{},
        .lpfnWndProc = WindowProc,
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .hInstance = hInstance,
        .hIcon = null,
        .hCursor = null,
        .hbrBackground = null,
        .lpszMenuName = MENU_NAME,
        .lpszClassName = CLASS_NAME,
    };

    // returning 0 means RegisterClassA failed
    if (win32.RegisterClassA(&wc) == 0)
        std.debug.panic("RegisterClass failed with {}", .{win32.GetLastError().fmt()});

    var hwnd: ?win32.HWND = undefined;
    hwnd = win32.CreateWindowExA(
        .{}, 
        CLASS_NAME
        , 
        "Learn to Program Windows", 
        win32.WS_OVERLAPPEDWINDOW, 
        win32.CW_USEDEFAULT, win32.CW_USEDEFAULT, win32.CW_USEDEFAULT, win32.CW_USEDEFAULT, 
        null, 
        null, 
        hInstance, 
        null
    ) orelse std.debug.panic("CreateWindow failed with {}", .{win32.GetLastError().fmt()});
    
    _ = win32.ShowWindow(hwnd, .{ .SHOWNORMAL = 1});

    var msg: win32.MSG = undefined;
    while (win32.GetMessageW(&msg, null, 0, 0) != 0) {
        _ = win32.TranslateMessage(&msg);
        _ = win32.DispatchMessageW(&msg);
    }
}

fn WindowProc(
    hWnd: win32.HWND, 
    Msg: u32, 
    wParam: win32.WPARAM, 
    lParam: win32.LPARAM
) callconv(WINAPI) win32.LRESULT {
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