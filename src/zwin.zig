pub const Window = @import("window.zig");
pub const FileMapped = @import("file_mapped.zig");

comptime {
    _ = @import("file_mapped.zig");
}