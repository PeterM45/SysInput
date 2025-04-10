//-----------------------------------------------------------------------------
// Windows API bindings for Zig
// Organized by functional areas
//-----------------------------------------------------------------------------

//=============================================================================
// BASIC TYPES AND HANDLES
//=============================================================================

// Basic Windows Types
pub const BOOL = i32;
pub const UINT = u32;
pub const DWORD = u32;
pub const WORD = u16;
pub const WCHAR = u16;
pub const LONG = i32;
pub const LPARAM = isize;
pub const WPARAM = usize;
pub const LRESULT = isize;
pub const ATOM = u16;
pub const COLORREF = u32; // RGB color value

// Handle Types
pub const HANDLE = *anyopaque;
pub const HWND = *anyopaque; // Window handle
pub const HINSTANCE = *anyopaque; // Instance handle
pub const HHOOK = HANDLE; // Hook handle
pub const HDC = *anyopaque; // Device context handle
pub const HFONT = *anyopaque; // Font handle
pub const HGDIOBJ = *anyopaque; // GDI object handle
pub const HBRUSH = *anyopaque; // Brush handle

//=============================================================================
// WINDOW MESSAGE CONSTANTS
//=============================================================================

// Basic Window Messages
pub const WM_CREATE = 0x0001;
pub const WM_DESTROY = 0x0002;
pub const WM_CLOSE = 0x0010;
pub const WM_PAINT = 0x000F;
pub const WM_ERASEBKGND = 0x0014;
pub const WM_USER = 0x0400;

// Input-related Window Messages
pub const WM_KEYDOWN = 0x0100;
pub const WM_KEYUP = 0x0101;
pub const WM_CHAR = 0x0102;
pub const WM_SYSKEYDOWN = 0x0104;
pub const WM_SYSKEYUP = 0x0105;
pub const WM_LBUTTONDOWN = 0x0201;

// Text-related Window Messages
pub const WM_GETTEXT = 0x000D;
pub const WM_SETTEXT = 0x000C;
pub const WM_GETTEXTLENGTH = 0x000E;
pub const WM_PASTE = 0x0302;

// Edit Control Messages
pub const EM_GETSEL = 0x00B0;
pub const EM_SETSEL = 0x00B1;
pub const EM_REPLACESEL = 0x00C2;
pub const EM_POSFROMCHAR = 0x00D6;

//=============================================================================
// KEYBOARD AND INPUT CONSTANTS
//=============================================================================

// Hook types
pub const WH_KEYBOARD_LL = 13;
pub const HC_ACTION = 0;

// Input types
pub const INPUT_KEYBOARD = 1;
pub const KEYEVENTF_KEYUP = 0x0002;
pub const KEYEVENTF_UNICODE = 0x0004;

// Virtual Key Constants
pub const VK_ESCAPE = 0x1B;
pub const VK_RETURN = 0x0D;
pub const VK_SPACE = 0x20;
pub const VK_BACK = 0x08; // Backspace
pub const VK_DELETE = 0x2E; // Delete key
pub const VK_LEFT = 0x25; // Left arrow
pub const VK_RIGHT = 0x27; // Right arrow
pub const VK_UP = 0x26; // Up arrow
pub const VK_DOWN = 0x28; // Down arrow
pub const VK_HOME = 0x24; // Home key
pub const VK_END = 0x23; // End key
pub const VK_TAB = 0x09; // Tab key
pub const VK_SHIFT = 0x10; // Shift key
pub const VK_CONTROL = 0x11; // Control key
pub const VK_MENU = 0x12; // Alt key
pub const VK_PRIOR = 0x21; // Page Up
pub const VK_NEXT = 0x22; // Page Down

//=============================================================================
// WINDOW STYLE AND APPEARANCE CONSTANTS
//=============================================================================

// Window positioning constants
pub const HWND_TOPMOST: ?HWND = @ptrFromInt(0xFFFFFFFF); // -1 as unsigned
pub const SWP_NOSIZE = 0x0001;
pub const SWP_NOMOVE = 0x0002;
pub const SWP_SHOWWINDOW = 0x0040;

// Window style constants
pub const WS_POPUP = 0x80000000;
pub const WS_BORDER = 0x00800000;
pub const WS_CAPTION = 0x00C00000;
pub const WS_EX_TOPMOST = 0x00000008;
pub const WS_EX_TOOLWINDOW = 0x00000080;
pub const WS_EX_NOACTIVATE = 0x08000000;
pub const WS_EX_LAYERED = 0x00080000;
pub const WS_EX_TRANSPARENT = 0x00000020;
pub const GWL_EXSTYLE = -20;
pub const CS_DROPSHADOW = 0x00020000;

// Window display commands
pub const SW_SHOW = 5;
pub const SW_SHOWNOACTIVATE = 4;
pub const SW_HIDE = 0;

//=============================================================================
// UI AND DRAWING CONSTANTS
//=============================================================================

// System metrics constants
pub const SM_CXSCREEN = 0;
pub const SM_CYSCREEN = 1;

// Text drawing constants
pub const DT_LEFT = 0x00000000;
pub const DT_SINGLELINE = 0x00000020;
pub const DT_VCENTER = 0x00000004;
pub const TRANSPARENT = 1;

// Drawing constants
pub const NULL_PEN = 8;
pub const CLEARTYPE_QUALITY = 5;
pub const BYTE = u8;

// Font constants
pub const FW_NORMAL = 400;
pub const ANSI_CHARSET = 0;
pub const OUT_DEFAULT_PRECIS = 0;
pub const CLIP_DEFAULT_PRECIS = 0;
pub const DEFAULT_QUALITY = 0;
pub const DEFAULT_PITCH = 0;
pub const FF_DONTCARE = 0;

// Stock object constants
pub const WHITE_BRUSH = 0;
pub const LTGRAY_BRUSH = 1;
pub const GRAY_BRUSH = 2;
pub const DKGRAY_BRUSH = 3;
pub const BLACK_BRUSH = 4;
pub const NULL_BRUSH = 5;
pub const WHITE_PEN = 6;
pub const BLACK_PEN = 7;
pub const PS_SOLID = 0;

// Cursor constants
pub const IDC_ARROW = 32512;

// Layered window constants
pub const LWA_ALPHA = 0x00000002;
pub const LWA_COLORKEY = 0x00000001;

// Clipboard constants
pub const CF_TEXT = 1;
pub const GMEM_MOVEABLE = 0x0002;

// Display metrics constants
pub const LOGPIXELSY = 90;
pub const LOGPIXELSX = 88;

//=============================================================================
// STRUCTURES
//=============================================================================

// Keyboard Hook Structure
pub const KBDLLHOOKSTRUCT = extern struct {
    vkCode: DWORD,
    scanCode: DWORD,
    flags: DWORD,
    time: DWORD,
    dwExtraInfo: usize,
};

// Point structure
pub const POINT = extern struct {
    x: c_long,
    y: c_long,
};

// Rectangle structure
pub const RECT = extern struct {
    left: c_long,
    top: c_long,
    right: c_long,
    bottom: c_long,
};

// Paint structure
pub const PAINTSTRUCT = extern struct {
    hdc: HDC,
    fErase: BOOL,
    rcPaint: RECT,
    fRestore: BOOL,
    fIncUpdate: BOOL,
    rgbReserved: [32]u8,
};

// Window class extended structure
pub const WNDCLASSEX = extern struct {
    cbSize: UINT,
    style: UINT,
    lpfnWndProc: *const fn (HWND, UINT, WPARAM, LPARAM) callconv(.C) LRESULT,
    cbClsExtra: c_int,
    cbWndExtra: c_int,
    hInstance: HINSTANCE,
    hIcon: ?HANDLE,
    hCursor: ?HANDLE,
    hbrBackground: HANDLE,
    lpszMenuName: ?[*:0]const u8,
    lpszClassName: [*:0]const u8,
    hIconSm: ?HANDLE,
};

// Message structure
pub const MSG = extern struct {
    hwnd: ?HWND,
    message: u32,
    wParam: WPARAM,
    lParam: LPARAM,
    time: DWORD,
    pt: POINT,
    lPrivate: DWORD,
};

// Input structure definitions
pub const KEYBDINPUT = extern struct {
    wVk: WORD,
    wScan: WORD,
    dwFlags: DWORD,
    time: DWORD,
    dwExtraInfo: usize,
    padding1: DWORD,
    padding2: DWORD,
};

pub const MOUSEINPUT = extern struct {
    dx: LONG,
    dy: LONG,
    mouseData: DWORD,
    dwFlags: DWORD,
    time: DWORD,
    dwExtraInfo: usize,
};

pub const HARDWAREINPUT = extern struct {
    uMsg: DWORD,
    wParamL: WORD,
    wParamH: WORD,
};

pub const INPUT = extern struct {
    type: DWORD,
    // Zig doesn't support C unions directly, so we use the largest member
    // and access the different fields depending on the type
    ki: KEYBDINPUT,
};

// GUI Thread Info structure
pub const GUITHREADINFO = extern struct {
    cbSize: DWORD,
    flags: DWORD,
    hwndActive: ?HWND,
    hwndFocus: ?HWND,
    hwndCapture: ?HWND,
    hwndMenuOwner: ?HWND,
    hwndMoveSize: ?HWND,
    hwndCaret: ?HWND,
    rcCaret: RECT,
};

//=============================================================================
// ERROR TYPES
//=============================================================================

// Common error types
pub const HookError = error{
    SetHookFailed,
    UnhookFailed,
    MessageLoopFailed,
};

//=============================================================================
// WINDOW MANAGEMENT FUNCTIONS
//=============================================================================

// Window creation and management
pub extern "user32" fn CreateWindowExA(
    dwExStyle: DWORD,
    lpClassName: [*:0]const u8,
    lpWindowName: [*:0]const u8,
    dwStyle: DWORD,
    x: c_int,
    y: c_int,
    nWidth: c_int,
    nHeight: c_int,
    hWndParent: ?HWND,
    hMenu: ?HANDLE,
    hInstance: HINSTANCE,
    lpParam: ?*anyopaque,
) callconv(.C) ?HWND;

pub extern "user32" fn ShowWindow(
    hWnd: HWND,
    nCmdShow: c_int,
) callconv(.C) BOOL;

pub extern "user32" fn UpdateWindow(
    hWnd: HWND,
) callconv(.C) BOOL;

pub extern "user32" fn DestroyWindow(
    hWnd: HWND,
) callconv(.C) BOOL;

pub extern "user32" fn GetClientRect(
    hWnd: HWND,
    lpRect: *RECT,
) callconv(.C) BOOL;

pub extern "user32" fn GetWindowRect(
    hWnd: HWND,
    lpRect: *RECT,
) callconv(.C) BOOL;

pub extern "user32" fn SetWindowPos(
    hWnd: HWND,
    hWndInsertAfter: ?HWND,
    X: c_int,
    Y: c_int,
    cx: c_int,
    cy: c_int,
    uFlags: UINT,
) callconv(.C) BOOL;

pub extern "user32" fn InvalidateRect(
    hWnd: ?HWND,
    lpRect: ?*const RECT,
    bErase: BOOL,
) callconv(.C) BOOL;

pub extern "user32" fn RegisterClassExA(
    lpWndClass: *const WNDCLASSEX,
) callconv(.C) ATOM;

pub extern "user32" fn UnregisterClassA(
    lpClassName: [*:0]const u8,
    hInstance: HINSTANCE,
) callconv(.C) BOOL;

pub extern "user32" fn DefWindowProcA(
    hWnd: HWND,
    Msg: UINT,
    wParam: WPARAM,
    lParam: LPARAM,
) callconv(.C) LRESULT;

pub extern "user32" fn GetActiveWindow() callconv(.C) ?HWND;
pub extern "user32" fn GetParent(hWnd: HWND) callconv(.C) ?HWND;
pub extern "user32" fn SetForegroundWindow(hWnd: HWND) callconv(.C) BOOL;

pub extern "user32" fn FindWindowExA(
    hWndParent: ?HWND,
    hWndChildAfter: ?HWND,
    lpszClass: [*:0]const u8,
    lpszWindow: ?[*:0]const u8,
) callconv(.C) ?HWND;

pub extern "user32" fn GetForegroundWindow() callconv(.C) ?HWND;
pub extern "user32" fn GetClassNameA(hWnd: ?HWND, lpClassName: [*:0]u8, nMaxCount: c_int) callconv(.C) c_int;
pub extern "user32" fn GetFocus() callconv(.C) ?HWND;

pub extern "user32" fn SendMessageA(hWnd: HWND, Msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.C) LRESULT;
pub extern "user32" fn PostMessageA(hWnd: HWND, Msg: UINT, wParam: WPARAM, lParam: LPARAM) callconv(.C) BOOL;

pub extern "user32" fn SetLayeredWindowAttributes(
    hwnd: HWND,
    crKey: COLORREF,
    bAlpha: BYTE,
    dwFlags: DWORD,
) callconv(.C) BOOL;

pub extern "gdi32" fn RoundRect(
    hdc: HDC,
    left: c_int,
    top: c_int,
    right: c_int,
    bottom: c_int,
    width: c_int,
    height: c_int,
) callconv(.C) BOOL;

//=============================================================================
// INPUT AND CURSOR FUNCTIONS
//=============================================================================

// Keyboard and mouse input
pub extern "user32" fn SendInput(
    cInputs: UINT,
    pInputs: *const INPUT,
    cbSize: c_int,
) callconv(.C) UINT;

// Cursor and caret management
pub extern "user32" fn GetCursorPos(
    lpPoint: *POINT,
) callconv(.C) BOOL;

pub extern "user32" fn GetCaretPos(
    lpPoint: *POINT,
) callconv(.C) BOOL;

pub extern "user32" fn ClientToScreen(
    hWnd: HWND,
    lpPoint: *POINT,
) callconv(.C) BOOL;

pub extern "user32" fn LoadCursorA(
    hInstance: ?HINSTANCE,
    lpCursorName: [*:0]const u8,
) callconv(.C) ?HANDLE;

// Thread and process info
pub extern "user32" fn GetWindowThreadProcessId(
    hWnd: HWND,
    lpdwProcessId: ?*DWORD,
) callconv(.C) DWORD;

pub extern "user32" fn GetGUIThreadInfo(
    idThread: DWORD,
    pgui: *GUITHREADINFO,
) callconv(.C) BOOL;

//=============================================================================
// GRAPHICS AND DRAWING FUNCTIONS
//=============================================================================

// Device context
pub extern "user32" fn GetDC(
    hWnd: ?HWND,
) callconv(.C) ?HDC;

pub extern "user32" fn ReleaseDC(
    hWnd: ?HWND,
    hDC: HDC,
) callconv(.C) c_int;

pub extern "gdi32" fn GetDeviceCaps(
    hdc: HDC,
    nIndex: c_int,
) callconv(.C) c_int;

// Paint functions
pub extern "user32" fn BeginPaint(
    hWnd: HWND,
    lpPaint: *PAINTSTRUCT,
) callconv(.C) HDC;

pub extern "user32" fn EndPaint(
    hWnd: HWND,
    lpPaint: *const PAINTSTRUCT,
) callconv(.C) BOOL;

pub extern "user32" fn FillRect(
    hDC: HDC,
    lprc: *const RECT,
    hbr: HANDLE,
) callconv(.C) c_int;

pub extern "user32" fn DrawTextA(
    hdc: HDC,
    lpchText: [*:0]const u8,
    cchText: c_int,
    lprc: *RECT,
    format: UINT,
) callconv(.C) c_int;

// GDI objects
pub extern "gdi32" fn GetStockObject(
    fnObject: c_int,
) callconv(.C) ?HGDIOBJ;

pub extern "gdi32" fn CreateFontA(
    cHeight: c_int,
    cWidth: c_int,
    cEscapement: c_int,
    cOrientation: c_int,
    cWeight: c_int,
    bItalic: DWORD,
    bUnderline: DWORD,
    bStrikeOut: DWORD,
    iCharSet: DWORD,
    iOutPrecision: DWORD,
    iClipPrecision: DWORD,
    iQuality: DWORD,
    iPitchAndFamily: DWORD,
    pszFaceName: [*:0]const u8,
) callconv(.C) ?HFONT;

pub extern "gdi32" fn CreateSolidBrush(
    color: COLORREF,
) callconv(.C) ?HBRUSH;

pub extern "gdi32" fn SelectObject(
    hdc: HDC,
    h: HGDIOBJ,
) callconv(.C) ?HGDIOBJ;

pub extern "gdi32" fn DeleteObject(
    ho: HGDIOBJ,
) callconv(.C) BOOL;

pub extern "gdi32" fn SetTextColor(
    hdc: HDC,
    color: COLORREF,
) callconv(.C) COLORREF;

pub extern "gdi32" fn SetBkMode(
    hdc: HDC,
    mode: c_int,
) callconv(.C) c_int;

//=============================================================================
// CLIPBOARD FUNCTIONS
//=============================================================================

pub extern "user32" fn OpenClipboard(hWndNewOwner: ?HWND) callconv(.C) BOOL;
pub extern "user32" fn CloseClipboard() callconv(.C) BOOL;
pub extern "user32" fn EmptyClipboard() callconv(.C) BOOL;
pub extern "user32" fn SetClipboardData(uFormat: UINT, hMem: ?HANDLE) callconv(.C) ?HANDLE;
pub extern "user32" fn GetClipboardData(uFormat: UINT) callconv(.C) ?HANDLE;

//=============================================================================
// MEMORY MANAGEMENT FUNCTIONS
//=============================================================================

pub extern "kernel32" fn GlobalAlloc(uFlags: UINT, dwBytes: usize) callconv(.C) ?HANDLE;
pub extern "kernel32" fn GlobalLock(hMem: HANDLE) callconv(.C) ?*anyopaque;
pub extern "kernel32" fn GlobalUnlock(hMem: HANDLE) callconv(.C) BOOL;
pub extern "kernel32" fn GlobalFree(hMem: HANDLE) callconv(.C) HANDLE;

//=============================================================================
// SYSTEM INFORMATION FUNCTIONS
//=============================================================================

pub extern "user32" fn GetSystemMetrics(
    nIndex: c_int,
) callconv(.C) c_int;

//=============================================================================
// UTILITY FUNCTIONS
//=============================================================================

// Miscellaneous utility functions
pub extern "kernel32" fn Sleep(dwMilliseconds: DWORD) callconv(.C) void;
pub extern "kernel32" fn lstrlenA(lpString: ?*const anyopaque) callconv(.C) c_int;

// Helper functions
pub inline fn makeIntResource(id: u16) [*:0]const u8 {
    return @ptrFromInt(id);
}

//=============================================================================
// IDIOMATIC ZIG WRAPPERS
//=============================================================================

// --- Window Management ---

// Original SafeWrapper functions
pub fn safeGetClassName(hwnd: ?HWND) ![]const u8 {
    var class_name: [256]u8 = undefined;
    const len = GetClassNameA(hwnd, @ptrCast(&class_name), class_name.len);
    if (len == 0) return error.GetClassNameFailed;
    return class_name[0..@as(usize, @intCast(len))];
}

pub fn safeGetFocus() !HWND {
    return GetFocus() orelse error.NoFocusedWindow;
}

pub fn safeGetForegroundWindow() !HWND {
    return GetForegroundWindow() orelse error.NoActiveWindow;
}

// camelCase API wrappers for common functions
pub fn getClassName(hwnd: ?HWND, className: [*:0]u8, maxCount: c_int) c_int {
    return GetClassNameA(hwnd, className, maxCount);
}

pub fn getFocus() ?HWND {
    return GetFocus();
}

pub fn getForegroundWindow() ?HWND {
    return GetForegroundWindow();
}

pub fn getActiveWindow() ?HWND {
    return GetActiveWindow();
}

pub fn getParent(hwnd: HWND) ?HWND {
    return GetParent(hwnd);
}

pub fn clientToScreen(hwnd: HWND, point: *POINT) BOOL {
    return ClientToScreen(hwnd, point);
}

pub fn getClientRect(hwnd: HWND, rect: *RECT) BOOL {
    return GetClientRect(hwnd, rect);
}

pub fn getWindowRect(hwnd: HWND, rect: *RECT) BOOL {
    return GetWindowRect(hwnd, rect);
}

pub fn getCaretPos(point: *POINT) BOOL {
    return GetCaretPos(point);
}

pub fn getCursorPos(point: *POINT) BOOL {
    return GetCursorPos(point);
}

pub fn setForegroundWindow(hwnd: HWND) BOOL {
    return SetForegroundWindow(hwnd);
}

pub fn findWindowEx(parent: ?HWND, childAfter: ?HWND, className: [*:0]const u8, windowName: ?[*:0]const u8) ?HWND {
    return FindWindowExA(parent, childAfter, className, windowName);
}

pub fn sendMessage(hwnd: HWND, msg: UINT, wParam: WPARAM, lParam: LPARAM) LRESULT {
    return SendMessageA(hwnd, msg, wParam, lParam);
}

pub fn postMessage(hwnd: HWND, msg: UINT, wParam: WPARAM, lParam: LPARAM) BOOL {
    return PostMessageA(hwnd, msg, wParam, lParam);
}

pub fn sendInput(inputCount: UINT, inputs: *const INPUT, inputSize: c_int) UINT {
    return SendInput(inputCount, inputs, inputSize);
}

pub fn setWindowPos(hwnd: HWND, insertAfter: ?HWND, x: c_int, y: c_int, cx: c_int, cy: c_int, flags: UINT) BOOL {
    return SetWindowPos(hwnd, insertAfter, x, y, cx, cy, flags);
}

pub fn getWindowThreadProcessId(hwnd: HWND, processId: ?*DWORD) DWORD {
    return GetWindowThreadProcessId(hwnd, processId);
}

pub fn getGUIThreadInfo(threadId: DWORD, info: *GUITHREADINFO) BOOL {
    return GetGUIThreadInfo(threadId, info);
}

// --- Device Context and Drawing ---

pub fn getDC(hwnd: ?HWND) ?HDC {
    return GetDC(hwnd);
}

pub fn releaseDC(hwnd: ?HWND, hdc: HDC) c_int {
    return ReleaseDC(hwnd, hdc);
}

pub fn beginPaint(hwnd: HWND, paint: *PAINTSTRUCT) HDC {
    return BeginPaint(hwnd, paint);
}

pub fn endPaint(hwnd: HWND, paint: *const PAINTSTRUCT) BOOL {
    return EndPaint(hwnd, paint);
}

pub fn fillRect(hdc: HDC, rect: *const RECT, brush: HANDLE) c_int {
    return FillRect(hdc, rect, brush);
}

pub fn drawText(hdc: HDC, text: [*:0]const u8, textLen: c_int, rect: *RECT, format: UINT) c_int {
    return DrawTextA(hdc, text, textLen, rect, format);
}

// --- Clipboard Operations ---

pub fn openClipboard(hwndOwner: ?HWND) BOOL {
    return OpenClipboard(hwndOwner);
}

pub fn closeClipboard() BOOL {
    return CloseClipboard();
}

pub fn emptyClipboard() BOOL {
    return EmptyClipboard();
}

pub fn setClipboardData(format: UINT, mem: ?HANDLE) ?HANDLE {
    return SetClipboardData(format, mem);
}

pub fn getClipboardData(format: UINT) ?HANDLE {
    return GetClipboardData(format);
}

// --- Memory Operations ---

pub fn globalAlloc(flags: UINT, bytes: usize) ?HANDLE {
    return GlobalAlloc(flags, bytes);
}

pub fn globalLock(mem: HANDLE) ?*anyopaque {
    return GlobalLock(mem);
}

pub fn globalUnlock(mem: HANDLE) BOOL {
    return GlobalUnlock(mem);
}

pub fn globalFree(mem: HANDLE) HANDLE {
    return GlobalFree(mem);
}

// --- System Information ---

pub fn getSystemMetrics(index: c_int) c_int {
    return GetSystemMetrics(index);
}

// --- Utility Functions ---

pub fn sleep(milliseconds: DWORD) void {
    return Sleep(milliseconds);
}
