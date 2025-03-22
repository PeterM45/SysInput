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

// Windows Message Constants
pub const WM_KEYDOWN = 0x0100;
pub const WM_KEYUP = 0x0101;
pub const WM_SYSKEYDOWN = 0x0104;
pub const WM_SYSKEYUP = 0x0105;
pub const WM_GETTEXT = 0x000D;
pub const WM_GETTEXTLENGTH = 0x000E;

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
