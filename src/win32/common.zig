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

// Windows Message Constants
pub const WM_KEYDOWN = 0x0100;
pub const WM_KEYUP = 0x0101;
pub const WM_SYSKEYDOWN = 0x0104;
pub const WM_SYSKEYUP = 0x0105;
pub const WM_GETTEXT = 0x000D;
pub const WM_GETTEXTLENGTH = 0x000E;
pub const WM_PAINT = 0x000F;
pub const WM_CLOSE = 0x0010;
pub const WM_DESTROY = 0x0002;
pub const WM_LBUTTONDOWN = 0x0201;
pub const WM_ERASEBKGND = 0x0014;

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
pub const WS_EX_NOACTIVATE = 0x08000000;

// Layered window constants
pub const LWA_ALPHA = 0x00000002;
pub const LWA_COLORKEY = 0x00000001;
pub const GWL_EXSTYLE = -20;
pub const PS_SOLID = 0;

// Additional window and control functions
pub extern "user32" fn GetForegroundWindow() callconv(.C) ?HWND;
pub extern "user32" fn GetFocus() callconv(.C) ?HWND;
pub extern "user32" fn SendMessageA(
    hWnd: HWND,
    Msg: UINT,
    wParam: WPARAM,
    lParam: LPARAM,
) callconv(.C) LRESULT;
