//! dx_window.zig
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
const ComPointer = @import("../com_pointer.zig").ComPointer;

const FrameCount: usize = 2;

const DXContext = @This();

dxgi_factory: ComPointer(win32.IDXGIFactory7),

device: ComPointer(win32.ID3D12Device),
cmd_queue: ComPointer(win32.ID3D12CommandQueue),

// cmd_allocator: ComPointer(win32.ID3D12CommandAllocator),
// cmd_list: ComPointer(win32.ID3D12GraphicsCommandList6),

// fence: ComPointer(win32.ID3D12Fence1),
// fence_value: u64 = 0,
// fence_event: ?win32.HANDLE = null,

pub fn init() !DXContext {
    // First create a DXGI factory
    var factory = ComPointer(win32.IDXGIFactory7).init();
    if (win32.FAILED(win32.CreateDXGIFactory2(0, win32.IID_IDXGIFactory, @as(**anyopaque, @ptrCast(factory.ptrPtr()))))) {
        return error.CreateFactoryFailed;
    }

    var device = ComPointer(win32.ID3D12Device).init();
    if (win32.FAILED(win32.D3D12CreateDevice(
        null, 
        win32.D3D_FEATURE_LEVEL_11_0, 
        win32.IID_ID3D12Device,
        @as(**anyopaque, @ptrCast(device.ptrPtr())
    )))) {
        return error.CreateDeviceFailed;
    }

    var cmdQueueDesc: win32.D3D12_COMMAND_QUEUE_DESC = undefined;
    cmdQueueDesc = .{ 
        .Type = win32.D3D12_COMMAND_LIST_TYPE_DIRECT,
        .Priority = @intFromEnum(win32.D3D12_COMMAND_QUEUE_PRIORITY_HIGH),
        .NodeMask = 0,
        .Flags = win32.D3D12_COMMAND_QUEUE_FLAG_NONE 
    };
    var cmd_queue = ComPointer(win32.ID3D12CommandQueue).init();
    if (device.ptr) |ptr| {
        if (win32.FAILED(ptr.vtable.CreateCommandQueue(
            device.ptr.?,
            &cmdQueueDesc, 
            win32.IID_ID3D12CommandQueue,
            @as(**anyopaque, @ptrCast(cmd_queue.ptrPtr())
        )))) {
            return error.CreateCommandQueueFailed;
        }
    }

    // var fence = ComPointer(win32.ID3D12Fence1).init();
    // const fence_value: u64 = 0;
    // if (device.ptr) |ptr| {
    //     if (win32.FAILED(ptr.vtable.CreateFence(
    //         device.ptr.?,
    //         fence_value,
    //         win32.D3D12_FENCE_FLAG_NONE, 
    //         win32.IID_ID3D12Fence1,
    //         @as(**anyopaque, @ptrCast(cmd_queue.ptrPtr())
    //     )))) {
    //         return error.CreateCommandQueueFailed;
    //     }
    // }


    return .{
        .dxgi_factory = factory,
        .device = device,
        .cmd_queue = cmd_queue,
    };
}

pub fn shutdown(self: *DXContext) void {
    _ = self.cmd_queue.release();
    _ = self.device.release();

    _ = self.dxgi_factory.release();
}
