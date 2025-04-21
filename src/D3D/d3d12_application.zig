//! d3d12_application.zig
const std = @import("std");
const windows = std.os.windows;
const WINAPI = windows.WINAPI;
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
const Window = @import("../window.zig");
const ComPointer = @import("com_pointer.zig").ComPointer;

const FrameCount: usize = 2;

const D3D12Application = @This();

fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    if (std.fmt.allocPrintZ(std.heap.page_allocator, fmt, args)) |msg| {
        _ = win32.MessageBoxA(null, msg, "Fatal Error", .{});
    } else |e| switch (e) {
        error.OutOfMemory => _ = win32.MessageBoxA(null, "Out of memory", "Fatal Error", .{}),
    }
    std.process.exit(1);
}

class: win32.WNDCLASSA = undefined,
hwnd: ?win32.HWND = null,
instance: win32.HINSTANCE = undefined,
should_close: bool = false,

should_resize: bool = false,

is_fullscreen: bool = false,

swap_chain: ComPointer(win32.IDXGISwapChain3) = undefined,
buffers: [FrameCount]ComPointer(win32.ID3D12Resource2) = undefined,
current_buffer_index: usize = 0,

message_callback: ?MessageCallback = null,
allocator: std.mem.Allocator,

/// Callback for handling window messages
pub const MessageCallback = *const fn (window: *D3D12Application, msg: u32, wparam: WPARAM, lparam: LPARAM) ?LRESULT;

/// Options for creating a window
pub const CreateOptions = struct {
    title: [:0]const u8 = "ZWin Window",
    class_name: [:0]const u8 = "ZWin_Window_Class",
    width: i32 = 1920,
    height: i32 = 1080,
    style: win32.WINDOW_STYLE = win32.WS_OVERLAPPEDWINDOW,
    ex_style: win32.WINDOW_EX_STYLE = win32.WS_EX_APPWINDOW,
    message_callback: ?MessageCallback = null,
};

pub fn init(allocator: std.mem.Allocator, options: CreateOptions) !*D3D12Application {
    const window = try allocator.create(D3D12Application);
    errdefer allocator.destroy(window);

    window.* = .{
        .instance = win32.GetModuleHandleA(null) orelse return error.InstanceNull,
        .hwnd = null,
        .message_callback = options.message_callback,
        .allocator = allocator,
    };

    try window.registerClass(options);
    try window.createWindow(options);
    try window.createSwapChain(options);
    
    return window;
}

pub fn deinit(self: *D3D12Application) void {
    if (self.hwnd) |window_handle| _ = win32.DestroyWindow(window_handle);
    _ = win32.UnregisterClassA(self.class.lpszClassName, self.instance);
    self.allocator.destroy(self);
}

/// Register the window class
fn registerClass(self: *D3D12Application, options: CreateOptions) !void {
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
fn createWindow(self: *D3D12Application, options: CreateOptions) !void {
    // Calculate the required window size based on desired client area
    var rect = RECT{
        .left = 0,
        .top = 0,
        .right = options.width,
        .bottom = options.height,
    };

    _ = win32.AdjustWindowRectEx(
        &rect,
        options.style,
        0,
        options.ex_style
    );

    const adjusted_width = rect.right - rect.left;
    const adjusted_height = rect.bottom - rect.top;

    self.hwnd = win32.CreateWindowExA(
        .{}, 
        self.class.lpszClassName, 
        options.title, 
        options.style, 
        win32.CW_USEDEFAULT, 
        win32.CW_USEDEFAULT, 
        adjusted_width, 
        adjusted_height, 
        null, 
        null, 
        self.instance, 
        self
    ) orelse fatal("CreateWindow failed, error={}", .{win32.GetLastError()});
}

fn createSwapChain(self: *D3D12Application, options: CreateOptions) !void {
    _ = self;
    // Describe swap chain
    var swd: win32.DXGI_SWAP_CHAIN_DESC1 = undefined;
    var sfd: win32.DXGI_SWAP_CHAIN_FULLSCREEN_DESC = undefined;

    swd = .{
        .Width = @intCast(options.width),
        .Height = @intCast(options.height),
        .Format = win32.DXGI_FORMAT_R8G8B8A8_UNORM,
        .Stereo = win32.FALSE,
        .SampleDesc = .{ .Count = 1, .Quality = 0 },
        .BufferUsage = win32.DXGI_USAGE_BACK_BUFFER | win32.DXGI_USAGE_RENDER_TARGET_OUTPUT,
        .BufferCount = FrameCount,
        .Scaling = win32.DXGI_SCALING_STRETCH,
        .SwapEffect = win32.DXGI_SWAP_EFFECT_FLIP_DISCARD,
        .AlphaMode = win32.DXGI_ALPHA_MODE_IGNORE,
        .Flags = @intFromEnum(win32.DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH) | @intFromEnum(win32.DXGI_SWAP_CHAIN_FLAG_ALLOW_TEARING),
    };

    sfd = .{
        .RefreshRate = .{ .Denominator = 0, .Numerator = 1 },
        .ScanlineOrdering = .UNSPECIFIED,
        .Scaling = .UNSPECIFIED,
        .Windowed = win32.FALSE 
    };


}

/// Show the window
pub fn show(self: *D3D12Application) void {
    _ = win32.ShowWindow(self.hwnd, win32.SW_SHOW);
    _ = win32.UpdateWindow(self.hwnd);
}

/// Hide the window
pub fn hide(self: *D3D12Application) void {
    _ = win32.ShowWindow(self.hwnd, win32.SW_HIDE);
}

/// Get client area dimensions
pub fn getClientSize(self: *D3D12Application) RECT {
    var rect: RECT = undefined;
    _ = win32.GetClientRect(self.hwnd, &rect);
    return rect;
}

/// Set window title
pub fn setTitle(self: *D3D12Application, title: [:0]const u8) void {
    _ = win32.SetWindowTextA(self.hwnd, title);
    self.title = title;
}

/// Main window procedure
fn WindowProc(hWnd: win32.HWND, Msg: u32, wParam: win32.WPARAM, lParam: win32.LPARAM) callconv(WINAPI) win32.LRESULT {
    var pThis: ?*D3D12Application = null;
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

    // Call the message callback if it exists
    if (pThis) |window| {
        if (window.message_callback) |callback| {
            if (callback(window, Msg, wParam, lParam)) |result| {
                return result;
            }
        }
    }

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