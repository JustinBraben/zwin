pub const ComPointer = @import("com_pointer.zig").ComPointer;
pub const FileMapped = @import("file_mapped.zig");
pub const Window = @import("window.zig");

comptime {
    _ = @import("com_pointer.zig");
    _ = @import("file_mapped.zig");
}