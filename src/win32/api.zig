/// Common Windows API types and constants
/// Used across different modules in the application

// Windows Type Definitions
pub const HINSTANCE = *anyopaque;
pub const HWND = *anyopaque;
pub const LPARAM = isize;
pub const WPARAM = usize;
pub const LRESULT = isize;
pub const HANDLE = *anyopaque;
pub const DWORD = u32;
pub const HHOOK = HANDLE;
pub const LONG = i32;
pub const UINT = u32;
pub const BOOL = i32;
pub const WCHAR = u16;
pub const ATOM = u16;
pub const HDC = *anyopaque; // Handle to Device Context
pub const COLORREF = u32; // RGB color value
pub const HFONT = *anyopaque; // Handle to Font
pub const HGDIOBJ = *anyopaque; // Handle to GDI Object
pub const HBRUSH = *anyopaque; // Handle to Brush

// Windows Message Constants
pub const WM_KEYDOWN = 0x0100;
pub const WM_KEYUP = 0x0101;
pub const WM_CHAR = 0x0102;
pub const WM_SYSKEYDOWN = 0x0104;
pub const WM_SYSKEYUP = 0x0105;
pub const WM_GETTEXT = 0x000D;
pub const WM_GETTEXTLENGTH = 0x000E;
pub const WM_PAINT = 0x000F;
pub const WM_CLOSE = 0x0010;
pub const WM_DESTROY = 0x0002;
pub const WM_LBUTTONDOWN = 0x0201;
pub const WM_ERASEBKGND = 0x0014;
pub const WM_CREATE = 0x0001;
pub const WM_USER = 0x0400;

// Edit control message constants
pub const EM_GETSEL = 0x00B0;
pub const EM_SETSEL = 0x00B1;
pub const EM_REPLACESEL = 0x00C2;

// Hook types
pub const WH_KEYBOARD_LL = 13;
pub const HC_ACTION = 0;

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

// System Metrics constants
pub const SM_CXSCREEN = 0;
pub const SM_CYSCREEN = 1;

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
pub const CS_DROPSHADOW = 0x00020000;

// Show window commands
pub const SW_SHOW = 5;
pub const SW_SHOWNOACTIVATE = 4;
pub const SW_HIDE = 0;

// Font constants
pub const FW_NORMAL = 400;
pub const ANSI_CHARSET = 0;
pub const OUT_DEFAULT_PRECIS = 0;
pub const CLIP_DEFAULT_PRECIS = 0;
pub const DEFAULT_QUALITY = 0;
pub const DEFAULT_PITCH = 0;
pub const FF_DONTCARE = 0;

// Drawing constants
pub const DT_LEFT = 0x00000000;
pub const DT_SINGLELINE = 0x00000020;
pub const DT_VCENTER = 0x00000004;
pub const TRANSPARENT = 1;

// Standard cursor IDs
pub const IDC_ARROW = 32512;

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

// Common error types
pub const HookError = error{
    SetHookFailed,
    UnhookFailed,
    MessageLoopFailed,
};

// Windows API Function declarations that are used in multiple modules
pub extern "user32" fn GetCursorPos(
    lpPoint: *POINT,
) callconv(.C) BOOL;

// Extended window styles
pub const WS_EX_LAYERED = 0x00080000;
pub const WS_EX_TRANSPARENT = 0x00000020;
pub const GWL_EXSTYLE = -20;
pub const PS_SOLID = 0;

// Stock object constants
pub const WHITE_BRUSH = 0;
pub const LTGRAY_BRUSH = 1;
pub const GRAY_BRUSH = 2;
pub const DKGRAY_BRUSH = 3;
pub const BLACK_BRUSH = 4;
pub const NULL_BRUSH = 5;
pub const WHITE_PEN = 6;
pub const BLACK_PEN = 7;

// GDI stock objects
pub extern "gdi32" fn GetStockObject(
    fnObject: c_int,
) callconv(.C) ?HGDIOBJ;

// Layered window constants
pub const LWA_ALPHA = 0x00000002;
pub const LWA_COLORKEY = 0x00000001;

// Additional window and control functions
pub extern "user32" fn GetForegroundWindow() callconv(.C) ?HWND;
pub extern "user32" fn GetFocus() callconv(.C) ?HWND;
pub extern "user32" fn SendMessageA(
    hWnd: HWND,
    Msg: UINT,
    wParam: WPARAM,
    lParam: LPARAM,
) callconv(.C) LRESULT;

// Additional window functions
pub extern "user32" fn RegisterClassExA(
    lpWndClass: *const WNDCLASSEX,
) callconv(.C) ATOM;

pub extern "user32" fn UnregisterClassA(
    lpClassName: [*:0]const u8,
    hInstance: HINSTANCE,
) callconv(.C) BOOL;

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

pub extern "user32" fn SetWindowPos(
    hWnd: HWND,
    hWndInsertAfter: ?HWND,
    X: c_int,
    Y: c_int,
    cx: c_int,
    cy: c_int,
    uFlags: UINT,
) callconv(.C) BOOL;

pub extern "user32" fn GetClientRect(
    hWnd: HWND,
    lpRect: *RECT,
) callconv(.C) BOOL;

pub extern "user32" fn InvalidateRect(
    hWnd: ?HWND,
    lpRect: ?*const RECT,
    bErase: BOOL,
) callconv(.C) BOOL;

pub extern "user32" fn DestroyWindow(
    hWnd: HWND,
) callconv(.C) BOOL;

pub extern "user32" fn LoadCursorA(
    hInstance: ?HINSTANCE,
    lpCursorName: [*:0]const u8,
) callconv(.C) ?HANDLE;

pub extern "user32" fn DefWindowProcA(
    hWnd: HWND,
    Msg: UINT,
    wParam: WPARAM,
    lParam: LPARAM,
) callconv(.C) LRESULT;

pub extern "user32" fn BeginPaint(
    hWnd: HWND,
    lpPaint: *PAINTSTRUCT,
) callconv(.C) HDC;

pub extern "user32" fn EndPaint(
    hWnd: HWND,
    lpPaint: *const PAINTSTRUCT,
) callconv(.C) BOOL;

pub extern "user32" fn GetParent(
    hWnd: HWND,
) callconv(.C) ?HWND;

pub extern "user32" fn PostMessageA(
    hWnd: HWND,
    Msg: UINT,
    wParam: WPARAM,
    lParam: LPARAM,
) callconv(.C) BOOL;

// GDI functions
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

pub extern "gdi32" fn SelectObject(
    hdc: HDC,
    h: HGDIOBJ,
) callconv(.C) ?HGDIOBJ;

pub extern "gdi32" fn DeleteObject(
    ho: HGDIOBJ,
) callconv(.C) BOOL;

pub extern "gdi32" fn CreateSolidBrush(
    color: COLORREF,
) callconv(.C) ?HBRUSH;

pub extern "user32" fn FillRect(
    hDC: HDC,
    lprc: *const RECT,
    hbr: HANDLE,
) callconv(.C) c_int;

pub extern "gdi32" fn SetTextColor(
    hdc: HDC,
    color: COLORREF,
) callconv(.C) COLORREF;

pub extern "gdi32" fn SetBkMode(
    hdc: HDC,
    mode: c_int,
) callconv(.C) c_int;

pub extern "user32" fn DrawTextA(
    hdc: HDC,
    lpchText: [*:0]const u8,
    cchText: c_int,
    lprc: *RECT,
    format: UINT,
) callconv(.C) c_int;

// Utility functions
pub inline fn makeIntResource(id: u16) [*:0]const u8 {
    return @ptrFromInt(id);
}
// Additional window positioning functions
pub extern "user32" fn GetCaretPos(
    lpPoint: *POINT,
) callconv(.C) BOOL;

pub extern "user32" fn ClientToScreen(
    hWnd: HWND,
    lpPoint: *POINT,
) callconv(.C) BOOL;

pub extern "user32" fn GetWindowRect(
    hWnd: HWND,
    lpRect: *RECT,
) callconv(.C) BOOL;

// GUI Thread Info constants
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

// Functions for getting GUI thread info
pub extern "user32" fn GetGUIThreadInfo(
    idThread: DWORD,
    pgui: *GUITHREADINFO,
) callconv(.C) BOOL;

// Add EM_POSFROMCHAR message
pub const EM_POSFROMCHAR = 0x00D6;

// Clipboard constants
pub const CF_TEXT = 1;
pub const GMEM_MOVEABLE = 0x0002;

// Clipboard functions
pub extern "user32" fn OpenClipboard(hWndNewOwner: ?HWND) callconv(.C) BOOL;
pub extern "user32" fn CloseClipboard() callconv(.C) BOOL;
pub extern "user32" fn EmptyClipboard() callconv(.C) BOOL;
pub extern "user32" fn SetClipboardData(uFormat: UINT, hMem: ?HANDLE) callconv(.C) ?HANDLE;
pub extern "user32" fn GetClipboardData(uFormat: UINT) callconv(.C) ?HANDLE;

// Global memory functions
pub extern "kernel32" fn GlobalAlloc(uFlags: UINT, dwBytes: usize) callconv(.C) ?HANDLE;
pub extern "kernel32" fn GlobalLock(hMem: HANDLE) callconv(.C) ?*anyopaque;
pub extern "kernel32" fn GlobalUnlock(hMem: HANDLE) callconv(.C) BOOL;
pub extern "kernel32" fn GlobalFree(hMem: HANDLE) callconv(.C) HANDLE;

// String functions
pub extern "kernel32" fn lstrlenA(lpString: ?*const anyopaque) callconv(.C) c_int;

// Additional windows messages
pub const WM_PASTE = 0x0302;

// Sleep function
pub extern "kernel32" fn Sleep(dwMilliseconds: DWORD) callconv(.C) void;

// SetForegroundWindow
pub extern "user32" fn SetForegroundWindow(hWnd: HWND) callconv(.C) BOOL;

// Get thread/process functions
pub extern "user32" fn GetWindowThreadProcessId(
    hWnd: HWND,
    lpdwProcessId: ?*DWORD,
) callconv(.C) DWORD;

// Window finding functions
pub extern "user32" fn FindWindowExA(
    hWndParent: ?HWND,
    hWndChildAfter: ?HWND,
    lpszClass: [*:0]const u8,
    lpszWindow: ?[*:0]const u8,
) callconv(.C) ?HWND;

pub extern "user32" fn GetActiveWindow() callconv(.C) ?HWND;

// Input simulation
pub const INPUT_KEYBOARD = 1;
pub const KEYEVENTF_KEYUP = 0x0002;
pub const KEYEVENTF_UNICODE = 0x0004;

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

// Additional input types
pub const WORD = u16;

// Function declarations
pub extern "user32" fn SendInput(
    cInputs: UINT,
    pInputs: *const INPUT,
    cbSize: c_int,
) callconv(.C) UINT;

// Device context functions
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

// Display metrics constants
pub const LOGPIXELSY = 90;
pub const LOGPIXELSX = 88;

// System metrics function
pub extern "user32" fn GetSystemMetrics(
    nIndex: c_int,
) callconv(.C) c_int;
