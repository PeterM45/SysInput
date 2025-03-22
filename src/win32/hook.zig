const std = @import("std");

// Windows Type Definitions
pub const HINSTANCE = *anyopaque;
pub const HWND = *anyopaque;
pub const LPARAM = isize;
pub const WPARAM = usize;
pub const LRESULT = isize;
pub const HANDLE = *anyopaque;
pub const DWORD = u32;
pub const HHOOK = HANDLE;

// Windows Constants
pub const WH_KEYBOARD_LL = 13;
pub const HC_ACTION = 0;

// Keyboard Message Constants
pub const WM_KEYDOWN = 0x0100;
pub const WM_KEYUP = 0x0101;
pub const WM_SYSKEYDOWN = 0x0104;
pub const WM_SYSKEYUP = 0x0105;

// Virtual Key Constants
pub const VK_ESCAPE = 0x1B;
pub const VK_RETURN = 0x0D;
pub const VK_SPACE = 0x20;
pub const VK_BACK = 0x08; // Backspace
pub const VK_DELETE = 0x2E; // Delete key
pub const VK_LEFT = 0x25; // Left arrow
pub const VK_RIGHT = 0x26; // Right arrow

/// Keyboard Low-Level Hook Structure
pub const KBDLLHOOKSTRUCT = extern struct {
    vkCode: DWORD,
    scanCode: DWORD,
    flags: DWORD,
    time: DWORD,
    dwExtraInfo: usize,
};

pub const POINT = extern struct {
    x: c_long,
    y: c_long,
};

pub const MSG = extern struct {
    hwnd: ?HWND,
    message: u32,
    wParam: WPARAM,
    lParam: LPARAM,
    time: DWORD,
    pt: POINT,
    lPrivate: DWORD,
};

// Windows API Function Declarations
pub extern "user32" fn SetWindowsHookExA(
    idHook: c_int,
    lpfn: *const fn (c_int, WPARAM, LPARAM) callconv(.C) LRESULT,
    hmod: HINSTANCE,
    dwThreadId: DWORD,
) callconv(.C) ?HHOOK;

pub extern "user32" fn UnhookWindowsHookEx(
    hhk: HHOOK,
) callconv(.C) c_int;

pub extern "user32" fn CallNextHookEx(
    hhk: ?HHOOK,
    nCode: c_int,
    wParam: WPARAM,
    lParam: LPARAM,
) callconv(.C) LRESULT;

pub extern "user32" fn GetMessageA(
    lpMsg: *MSG,
    hWnd: ?HWND,
    wMsgFilterMin: u32,
    wMsgFilterMax: u32,
) callconv(.C) c_int;

pub extern "user32" fn TranslateMessage(
    lpMsg: *const MSG,
) callconv(.C) c_int;

pub extern "user32" fn DispatchMessageA(
    lpMsg: *const MSG,
) callconv(.C) LRESULT;

pub extern "kernel32" fn GetModuleHandleA(
    lpModuleName: ?[*:0]const u8,
) callconv(.C) HINSTANCE;

/// Error type for hook operations
pub const HookError = error{
    SetHookFailed,
    UnhookFailed,
    MessageLoopFailed,
};

/// Global hook handle
pub var g_hook: ?HHOOK = null;
