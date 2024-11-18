const std = @import("std");
const win32 = @import("zigwin32").everything;

const Window = @This();

name: ?[*:0]const u8,
style: win32.WINDOW_STYLE,
ex_style: win32.WINDOW_EX_STYLE,
size_x: c_int = 400,
size_y: c_int = 200,

pub fn init() Window {

}