const std = @import("std");
const zwin = @import("zwin");

pub fn main() !void {
    // Initialize memory allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var example_window = try zwin.Window.init(allocator, .{});
    defer example_window.deinit();

    // Show the window
    example_window.show();

    // Run the message loop
    zwin.Window.runMessageLoop();
}
