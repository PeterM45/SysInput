const std = @import("std");
const common = @import("common.zig");

// Re-export common types
pub usingnamespace common;

// Windows API Function Declarations
pub extern "user32" fn SetWindowsHookExA(
    idHook: c_int,
    lpfn: *const fn (c_int, common.WPARAM, common.LPARAM) callconv(.C) common.LRESULT,
    hmod: common.HINSTANCE,
    dwThreadId: common.DWORD,
) callconv(.C) ?common.HHOOK;

pub extern "user32" fn UnhookWindowsHookEx(
    hhk: common.HHOOK,
) callconv(.C) c_int;

pub extern "user32" fn CallNextHookEx(
    hhk: ?common.HHOOK,
    nCode: c_int,
    wParam: common.WPARAM,
    lParam: common.LPARAM,
) callconv(.C) common.LRESULT;

pub extern "user32" fn GetMessageA(
    lpMsg: *common.MSG,
    hWnd: ?common.HWND,
    wMsgFilterMin: u32,
    wMsgFilterMax: u32,
) callconv(.C) c_int;

pub extern "user32" fn TranslateMessage(
    lpMsg: *const common.MSG,
) callconv(.C) c_int;

pub extern "user32" fn DispatchMessageA(
    lpMsg: *const common.MSG,
) callconv(.C) common.LRESULT;

pub extern "kernel32" fn GetModuleHandleA(
    lpModuleName: ?[*:0]const u8,
) callconv(.C) common.HINSTANCE;

/// Global hook handle
pub var g_hook: ?common.HHOOK = null;
