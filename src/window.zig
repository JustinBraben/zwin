const std = @import("std");
const WINAPI = std.os.windows.WINAPI;
const win32 = @import("win32").everything;
const HWND = win32.HWND;
const HINSTANCE = win32.HINSTANCE;
const WPARAM = win32.WPARAM;
const LPARAM = win32.LPARAM;
const LRESULT = win32.LRESULT;
const RECT = win32.RECT;
const L = win32.L;
const POINT = win32.POINT;
const MSG = win32.MSG;

const Window = @This();

fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    if (std.fmt.allocPrintZ(std.heap.page_allocator, fmt, args)) |msg| {
        _ = win32.MessageBoxA(null, msg, "Fatal Error", .{});
    } else |e| switch (e) {
        error.OutOfMemory => _ = win32.MessageBoxA(null, "Out of memory", "Fatal Error", .{}),
    }
    std.process.exit(1);
}

hwnd: ?win32.HWND = null,
instance: win32.HINSTANCE = undefined,
class: win32.WNDCLASSA = undefined,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, options: CreateOptions) !*Window {
    const window = try allocator.create(Window);
    errdefer allocator.destroy(window);

    window.* = .{
        .instance = win32.GetModuleHandleA(null) orelse return error.InstanceNull,
        .hwnd = null,
        .allocator = allocator,
    };

    try window.registerClass(options);
    try window.createWindow();
    
    return window;
}

pub fn deinit(self: *Window) void {
    if (self.hwnd) |window_handle| _ = win32.DestroyWindow(window_handle);
    _ = win32.UnregisterClassA(self.class.lpszClassName, self.instance);
    self.allocator.destroy(self);
}

/// Register the window class
fn registerClass(self: *Window, options: CreateOptions) !void {
    self.class = .{
        .style = .{},
        .lpfnWndProc = WindowProc,
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .hInstance = win32.GetModuleHandleA(null) orelse return error.InstanceNull,
        .hIcon = null,
        .hCursor = null,
        .hbrBackground = null,
        .lpszMenuName = null,
        .lpszClassName = options.class_name,
    };

    // returning FAIL (0) means RegisterClassA failed
    if (win32.RegisterClassA(&self.class) == win32.FAIL) {
        fatal("RegisterClass failed, error={}", .{win32.GetLastError()});
    }
}

/// Create the window
fn createWindow(self: *Window) !void {
    self.hwnd = win32.CreateWindowExA(.{}, self.class.lpszClassName, "Learn to Program Windows", win32.WS_OVERLAPPEDWINDOW, win32.CW_USEDEFAULT, win32.CW_USEDEFAULT, win32.CW_USEDEFAULT, win32.CW_USEDEFAULT, null, null, self.instance, null) orelse fatal("CreateWindow failed, error={}", .{win32.GetLastError()});
}

/// Show the window
pub fn show(self: *Window) void {
    _ = win32.ShowWindow(self.hwnd, win32.SW_SHOW);
    _ = win32.UpdateWindow(self.hwnd);
}

/// Hide the window
pub fn hide(self: *Window) void {
    _ = win32.ShowWindow(self.hwnd, win32.SW_HIDE);
}

/// Get client area dimensions
pub fn getClientSize(self: *Window) RECT {
    var rect: RECT = undefined;
    _ = win32.GetClientRect(self.hwnd, &rect);
    return rect;
}

/// Set window title
pub fn setTitle(self: *Window, title: [:0]const u8) void {
    _ = win32.SetWindowTextA(self.hwnd, title);
    self.title = title;
}

pub fn run(self: *Window) !void {
    _ = win32.ShowWindow(self.hwnd, .{ .SHOWNORMAL = 1 });

    var msg: win32.MSG = undefined;
    while (win32.GetMessageW(&msg, null, 0, 0) != 0) {
        _ = win32.TranslateMessage(&msg);
        _ = win32.DispatchMessageW(&msg);
    }
}

/// Main window procedure
fn WindowProc(hWnd: win32.HWND, Msg: u32, wParam: win32.WPARAM, lParam: win32.LPARAM) callconv(WINAPI) win32.LRESULT {
    var pThis: ?*Window = null;
    if (Msg == win32.WM_NCCREATE) {
        const pCreate: *win32.CREATESTRUCTA = @ptrFromInt(@as(usize, @bitCast(lParam)));
        pThis = @ptrCast(@alignCast(pCreate.lpCreateParams));
        _ = win32.setWindowLongPtrA(hWnd, @intFromEnum(win32.GWL_USERDATA), @bitCast(@intFromPtr(pThis)));
        if (pThis) |window| {
            window.*.hwnd = hWnd;
        }
    }
    else {
        pThis = @ptrFromInt(@as(usize, @bitCast(win32.getWindowLongPtrA(hWnd, @intFromEnum(win32.GWL_USERDATA)))));
    }

    // TODO: Call the message callback if it exists
    
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

/// Run the message loop until the window is closed
pub fn runMessageLoop() void {
    var msg: MSG = undefined;
    while (win32.GetMessageA(&msg, null, 0, 0) != 0) {
        _ = win32.TranslateMessage(&msg);
        _ = win32.DispatchMessageA(&msg);
    }
}

/// Callback for handling window messages
pub const MessageCallback = fn (window: *Window, msg: u32, wparam: WPARAM, lparam: LPARAM) ?LRESULT;

/// Options for creating a window
pub const CreateOptions = struct {
    title: [:0]const u8 = "ZWin Window",
    class_name: [:0]const u8 = "ZWin_Window_Class",
    width: i32 = 800,
    height: i32 = 600,
    style: win32.WINDOW_STYLE = win32.WS_OVERLAPPEDWINDOW,
    ex_style: u32 = 0,
    message_callback: ?MessageCallback = null,
};