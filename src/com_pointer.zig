//! com_ptr.zig

const std = @import("std");
const testing = std.testing;
const windows = std.os.windows;
const WINAPI = std.os.windows.WINAPI;
const win32 = @import("win32").everything;
const ULONG = windows.ULONG;
const HRESULT = win32.HRESULT;
const S_OK = win32.S_OK;
const IUnknown = win32.IUnknown;

pub fn ComPointer(comptime CT: type) type {
    // We don't verify COM interface type here as marlersoft zigwin32 uses a different structure
    // COM interfaces are represented as extern unions with IUnknown field

    return struct {
        const Self = @This();

        // The raw pointer
        ptr: ?*CT = null,

        /// Default constructor - creates an empty ComPointer
        pub fn init() Self {
            return Self{ .ptr = null };
        }

        /// Construct from raw pointer (adds reference)
        pub fn initWithPtr(pointer: ?*CT) Self {
            var self = Self{ .ptr = pointer };
            if (self.ptr != null) {
                _ = self.ptr.?.IUnknown.AddRef();
            }
            return self;
        }

        /// Destructor - releases the reference
        pub fn deinit(self: *Self) void {
            _ = self.clearPointer();
        }

        /// Release the reference and clear the pointer
        pub fn release(self: *Self) ULONG {
            return self.clearPointer();
        }

        /// Get a reference (adds ref)
        pub fn getRef(self: *Self) ?*CT {
            if (self.ptr) |p| {
                _ = p.IUnknown.AddRef();
                return p;
            }
            return null;
        }

        /// Get the raw pointer (no AddRef)
        pub fn get(self: *Self) ?*CT {
            return self.ptr;
        }

        /// Query for another interface
        pub fn queryInterface(self: *Self, comptime T: type, other: *ComPointer(T), errorCode: ?*HRESULT) bool {
            if (self.ptr) |p| {
                var raw_ptr: ?*T = null;
                const result = p.IUnknown.QueryInterface(T.IID, @as(*?*anyopaque, @ptrCast(&raw_ptr)));
                if (errorCode) |ec| {
                    ec.* = result;
                }
                
                if (result == S_OK) {
                    // Release any existing reference in other
                    _ = other.clearPointer();
                    other.ptr = raw_ptr;
                    return true;
                }
            }
            return false;
        }

        /// Compare with another ComPointer
        pub fn eql(self: Self, other: Self) bool {
            return self.ptr == other.ptr;
        }

        /// Compare with a raw pointer
        pub fn eqlPtr(self: Self, other: ?*CT) bool {
            return self.ptr == other;
        }

        /// Check if the pointer is not null
        pub fn isValid(self: Self) bool {
            return self.ptr != null;
        }

        /// Get pointer address for use with COM functions that output a pointer
        pub fn ptrPtr(self: *Self) **CT {
            return @ptrCast(&self.ptr);
        }

        /// Assign from another ComPointer (copy)
        pub fn assign(self: *Self, other: Self) void {
            _ = self.clearPointer();
            if (other.ptr) |p| {
                self.ptr = p;
                _ = p.IUnknown.AddRef();
            }
        }

        /// Assign from another ComPointer (move)
        pub fn move(self: *Self, other: *Self) void {
            _ = self.clearPointer();
            self.ptr = other.ptr;
            other.ptr = null;
        }

        /// Assign from raw pointer
        pub fn assignPtr(self: *Self, pointer: ?*CT) void {
            _ = self.clearPointer();
            self.ptr = pointer;
            if (self.ptr != null) {
                _ = self.ptr.?.IUnknown.AddRef();
            }
        }

        // Private helper methods
        fn clearPointer(self: *Self) ULONG {
            var newRef: ULONG = 0;
            if (self.ptr) |p| {
                newRef = p.IUnknown.Release();
                self.ptr = null;
            }
            return newRef;
        }
    };
}

test "ComPointer basic usage" {
    const MyDXGIFactory = ComPointer(win32.IDXGIFactory);
    const MyDXGIAdapter = ComPointer(win32.IDXGIAdapter);
    var hr: HRESULT = undefined;

    // First create a DXGI factory
    var factory = MyDXGIFactory.init();
    defer factory.deinit();

    hr = win32.CreateDXGIFactory(
        win32.IID_IDXGIFactory,
        @as(**anyopaque, @ptrCast(factory.ptrPtr()))
    );

    var adapter = MyDXGIAdapter.init();
    defer adapter.deinit();

    if (factory.ptr) |fptr| {
        hr = fptr.EnumAdapters(0, adapter.ptrPtr());
        try testing.expectEqual(win32.S_OK, hr);
    }

    var desc: win32.DXGI_ADAPTER_DESC = undefined;
    if (adapter.ptr) |ptr| {
        hr = ptr.GetDesc(&desc);
        try testing.expectEqual(win32.S_OK, hr);

        // Or access through the IUnknown interface
        // For example: adapter.ptr.?.IUnknown.AddRef()
        const ref = ptr.IUnknown.AddRef();
        try testing.expectEqual(2, ref);
    }
}