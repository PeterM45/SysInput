const std = @import("std");
const api = @import("api.zig");

// Re-export api types
pub usingnamespace api;

// Windows API Function Declarations
pub extern "user32" fn SetWindowsHookExA(
    idHook: c_int,
    lpfn: *const fn (c_int, api.WPARAM, api.LPARAM) callconv(.C) api.LRESULT,
    hmod: api.HINSTANCE,
    dwThreadId: api.DWORD,
) callconv(.C) ?api.HHOOK;

pub extern "user32" fn UnhookWindowsHookEx(
    hhk: api.HHOOK,
) callconv(.C) c_int;

pub extern "user32" fn CallNextHookEx(
    hhk: ?api.HHOOK,
    nCode: c_int,
    wParam: api.WPARAM,
    lParam: api.LPARAM,
) callconv(.C) api.LRESULT;

pub extern "user32" fn GetMessageA(
    lpMsg: *api.MSG,
    hWnd: ?api.HWND,
    wMsgFilterMin: u32,
    wMsgFilterMax: u32,
) callconv(.C) c_int;

pub extern "user32" fn TranslateMessage(
    lpMsg: *const api.MSG,
) callconv(.C) c_int;

pub extern "user32" fn DispatchMessageA(
    lpMsg: *const api.MSG,
) callconv(.C) api.LRESULT;

pub extern "kernel32" fn GetModuleHandleA(
    lpModuleName: ?[*:0]const u8,
) callconv(.C) api.HINSTANCE;

/// Global hook handle
pub var g_hook: ?api.HHOOK = null;
