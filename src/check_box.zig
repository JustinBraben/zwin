//! check_box.zig
const std = @import("std");
const WINAPI = std.os.windows.WINAPI;
const win32 = @import("win32").everything;
const HWND = win32.HWND;
const HINSTANCE = win32.HINSTANCE;
const WPARAM = win32.WPARAM;
const LPARAM = win32.LPARAM;
const LRESULT = win32.LRESULT;
const RECT = win32.RECT;

const CheckBox = @This();

fn fatal(comptime fmt: []const u8, args: anytype) noreturn {
    if (std.fmt.allocPrintZ(std.heap.page_allocator, fmt, args)) |msg| {
        _ = win32.MessageBoxA(null, msg, "Fatal Error", .{});
    } else |e| switch (e) {
        error.OutOfMemory => _ = win32.MessageBoxA(null, "Out of memory", "Fatal Error", .{}),
    }
    std.process.exit(1);
}

hwnd: ?win32.HWND = null,
parent_hwnd: win32.HWND,
text: [:0]const u8,
checked: bool = false,
id: u32,
allocator: std.mem.Allocator,
click_callback: ?ClickCallback = null,

/// Callback for handling checkbox clicks
pub const ClickCallback = *const fn (checkbox: *CheckBox, checked: bool) void;

/// Options for creating a checkbox
pub const CreateOptions = struct {
    text: [:0]const u8 = "Checkbox",
    x: i32 = 10,
    y: i32 = 10,
    width: i32 = 120,
    height: i32 = 25,
    id: u32 = 1001,
    checked: bool = false,
    enabled: bool = true,
    visible: bool = true,
    click_callback: ?ClickCallback = null,
    style: win32.WINDOW_STYLE = .{},
};

pub fn init(allocator: std.mem.Allocator, parent_hwnd: win32.HWND, options: CreateOptions) !*CheckBox {
    const checkbox = try allocator.create(CheckBox);
    errdefer allocator.destroy(checkbox);

    checkbox.* = .{
        .hwnd = null,
        .parent_hwnd = parent_hwnd,
        .text = options.text,
        .checked = options.checked,
        .id = options.id,
        .allocator = allocator,
        .click_callback = options.click_callback,
    };

    try checkbox.createCheckBox(options);
    
    return checkbox;
}

pub fn deinit(self: *CheckBox) void {
    if (self.hwnd) |handle| _ = win32.DestroyWindow(handle);
    self.allocator.destroy(self);
}

/// Create the checkbox control
fn createCheckBox(self: *CheckBox, options: CreateOptions) !void {
    // var style = win32.WS_CHILD | win32.WS_TABSTOP | win32.BS_AUTOCHECKBOX;
    var style: win32.WINDOW_STYLE = .{ .CHILD = 1, .TABSTOP = 1 };
    
    // Add additional styles
    if (options.visible) style.VISIBLE = 1;
    if (!options.enabled) style.DISABLED = 1;
    
    // Combine with custom styles
    // style |= @bitCast(options.style);
    // options.style.CHILD = style.CHILD;
    // options.style.TABSTOP = style.TABSTOP;
    // options.style.VISIBLE = style.VISIBLE;
    // options.style.TABSTOP = style.DISABLED;

    self.hwnd = win32.CreateWindowExA(
        .{},
        "BUTTON",
        options.text,
        style,
        options.x,
        options.y,
        options.width,
        options.height,
        self.parent_hwnd,
        @ptrFromInt(options.id),
        win32.GetModuleHandleA(null),
        null
    ) orelse fatal("CreateWindow failed for checkbox, error={}", .{win32.GetLastError()});

    // Set initial checked state
    if (options.checked) {
        self.setChecked(true);
    }
}

/// Set the checked state
pub fn setChecked(self: *CheckBox, checked: bool) void {
    const state: win32.DLG_BUTTON_CHECK_STATE = if (checked) win32.BST_CHECKED else win32.BST_UNCHECKED;
    _ = win32.SendMessageA(self.hwnd, win32.BM_SETCHECK, state, 0);
    self.checked = checked;
}

/// Get the checked state
pub fn isChecked(self: *CheckBox) bool {
    const result = win32.SendMessageA(self.hwnd, win32.BM_GETCHECK, 0, 0);
    self.checked = (result == win32.BST_CHECKED);
    return self.checked;
}

/// Set the checkbox text
pub fn setText(self: *CheckBox, text: [:0]const u8) void {
    _ = win32.SetWindowTextA(self.hwnd, text);
    self.text = text;
}

/// Get the checkbox text
pub fn getText(self: *CheckBox, buffer: []u8) ![]u8 {
    const len = win32.GetWindowTextA(self.hwnd, buffer.ptr, @intCast(buffer.len));
    if (len == 0) return error.GetTextFailed;
    return buffer[0..@intCast(len)];
}

/// Enable or disable the checkbox
pub fn setEnabled(self: *CheckBox, enabled: bool) void {
    _ = win32.EnableWindow(self.hwnd, if (enabled) 1 else 0);
}

/// Show or hide the checkbox
pub fn setVisible(self: *CheckBox, visible: bool) void {
    const cmd: i32 = if (visible) win32.SW_SHOW else win32.SW_HIDE;
    _ = win32.ShowWindow(self.hwnd, cmd);
}

/// Move the checkbox to a new position
pub fn move(self: *CheckBox, x: i32, y: i32) void {
    _ = win32.SetWindowPos(
        self.hwnd,
        null,
        x,
        y,
        0,
        0,
        win32.SWP_NOSIZE | win32.SWP_NOZORDER
    );
}

/// Resize the checkbox
pub fn resize(self: *CheckBox, width: i32, height: i32) void {
    _ = win32.SetWindowPos(
        self.hwnd,
        null,
        0,
        0,
        width,
        height,
        win32.SWP_NOMOVE | win32.SWP_NOZORDER
    );
}

/// Get the checkbox position and size
pub fn getBounds(self: *CheckBox) RECT {
    var rect: RECT = undefined;
    _ = win32.GetWindowRect(self.hwnd, &rect);
    
    // Convert to client coordinates relative to parent
    var top_left = win32.POINT{ .x = rect.left, .y = rect.top };
    var bottom_right = win32.POINT{ .x = rect.right, .y = rect.bottom };
    
    _ = win32.ScreenToClient(self.parent_hwnd, &top_left);
    _ = win32.ScreenToClient(self.parent_hwnd, &bottom_right);
    
    return RECT{
        .left = top_left.x,
        .top = top_left.y,
        .right = bottom_right.x,
        .bottom = bottom_right.y,
    };
}

/// Handle checkbox click (call this from parent window's message handler)
pub fn handleClick(self: *CheckBox) void {
    // Update internal state
    _ = self.isChecked();
    
    // Call callback if set
    if (self.click_callback) |callback| {
        callback(self, self.checked);
    }
}

/// Set the click callback
pub fn setClickCallback(self: *CheckBox, callback: ?ClickCallback) void {
    self.click_callback = callback;
}