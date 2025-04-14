const std = @import("std");
const zwin = @import("zwin");
const win32 = @import("win32").everything;

pub fn main() !void {
    // Initialize memory allocator
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var example_window = try zwin.Window.init(allocator, .{
        .title = "ZWin Test Application",
        .class_name = "ZWin_Test_Window",
        .width = 600,
        .height = 480,
        .message_callback = handleMessage,
    });
    defer example_window.deinit();

    // Show the window
    example_window.show();

    // Run the message loop
    zwin.Window.runMessageLoop();
}

fn handleMessage(window: *zwin.Window, msg: u32, wparam: win32.WPARAM, _: win32.LPARAM) ?win32.LRESULT {
    switch (msg) {
        win32.WM_PAINT => {
            var ps: win32.PAINTSTRUCT = undefined;
            const hdc = win32.BeginPaint(window.hwnd, &ps);
            defer _ = win32.EndPaint(window.hwnd, &ps);

            // Get client area size
            const rect = window.getClientSize();
            const width = rect.right - rect.left;
            const height = rect.bottom - rect.top;

            // Create a message to display
            const message = "Hello from ZWin!";
            
            // Setup text drawing
            _ = win32.SetBkMode(hdc, win32.TRANSPARENT);
            _ = win32.SetTextColor(hdc, 0x00000000);

            // Draw text centered in window
            var text_rect = win32.RECT{
                .left = 0,
                .top = 0,
                .right = width,
                .bottom = height,
            };
            
            _ = win32.DrawTextA(
                hdc,
                message,
                @intCast(message.len),
                &text_rect,
                .{ .CENTER = 1, .VCENTER = 1, .SINGLELINE = 1}
            );

            return 0;
        },
        win32.WM_KEYDOWN => {
            // Exit application on ESC key
            if (wparam == @intFromEnum(win32.VK_ESCAPE)) {
                _ = win32.PostMessageA(window.hwnd, win32.WM_CLOSE, 0, 0);
                return 0;
            }
            return null;
        },
        else => return null,
    }
}