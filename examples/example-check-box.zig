const std = @import("std");
const zwin = @import("zwin");
const Window = zwin.Window;
const Checkbox = zwin.CheckBox;
const win32 = @import("win32").everything;

// Example message callback for the window
fn windowMessageCallback(window: *Window, msg: u32, wparam: win32.WPARAM, lparam: win32.LPARAM) ?win32.LRESULT {
    switch (msg) {
        win32.WM_COMMAND => {
            const notification = @as(u16, @intCast((wparam >> 16) & 0xFFFF));
            const control_id = @as(u16, @intCast(wparam & 0xFFFF));
            
            // Handle checkbox clicks
            if (notification == win32.BN_CLICKED) {
                // You would need to maintain a map/array of your checkboxes
                // and find the one with the matching ID, then call handleClick()
                // For this example, assume we have a checkbox with ID 1001
                if (control_id == 1001) {
                    // Get your checkbox instance and call handleClick
                    // checkbox.handleClick();
                }
                return 0;
            }
        },
        else => {},
    }
    return null; // Let default processing handle other messages
}

// Example checkbox click callback
fn onCheckBoxClick(checkbox: *Checkbox, checked: bool) void {
    std.debug.print("Checkbox '{}' is now: {}\n", .{ checkbox.text, if (checked) "checked" else "unchecked" });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create window
    const window = try Window.init(allocator, .{
        .title = "Checkbox Example",
        .width = 400,
        .height = 300,
        .message_callback = windowMessageCallback,
    });
    defer window.deinit();

    // Create checkbox
    const checkbox = try Checkbox.init(allocator, window.hwnd.?, .{
        .text = "Enable Feature",
        .x = 20,
        .y = 20,
        .width = 150,
        .height = 25,
        .id = 1001,
        .checked = false,
        .click_callback = onCheckBoxClick,
    });
    defer checkbox.deinit();

    // Show window
    window.show();

    // Run message loop
    Window.runMessageLoop();
}