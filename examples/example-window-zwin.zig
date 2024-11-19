const std = @import("std");
const zwin = @import("zwin");

pub fn main() !void {
    const CLASS_NAME = "Sample Window Class";
    const MENU_NAME = "Sample Window Menu";

    var example_window = try zwin.Window.init(CLASS_NAME, MENU_NAME);
    defer example_window.deinit();

    try example_window.run();
}