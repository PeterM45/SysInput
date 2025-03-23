const std = @import("std");
const sysinput = @import("../sysinput.zig");

const api = sysinput.win32.api;

// Typical text field window class names
const TEXT_FIELD_CLASS_NAMES = [_][]const u8{
    "Edit",
    "RichEdit",
    "RichEdit20W",
    "RichEdit20A",
    "RichEdit50W",
    "RICHEDIT60W",
    "TextBox",
};

// Windows API function declarations for text field detection
pub extern "user32" fn GetForegroundWindow() callconv(.C) ?api.HWND;
pub extern "user32" fn GetClassNameA(hWnd: api.HWND, lpClassName: [*:0]u8, nMaxCount: c_int) callconv(.C) c_int;
pub extern "user32" fn GetFocus() callconv(.C) ?api.HWND;
pub extern "user32" fn GetWindowThreadProcessId(hWnd: api.HWND, lpdwProcessId: ?*api.DWORD) callconv(.C) api.DWORD;
pub extern "user32" fn SendMessageA(hWnd: api.HWND, Msg: api.UINT, wParam: api.WPARAM, lParam: api.LPARAM) callconv(.C) api.LRESULT;
pub extern "user32" fn PostMessageA(hWnd: api.HWND, Msg: api.UINT, wParam: api.WPARAM, lParam: api.LPARAM) callconv(.C) api.BOOL;

// Error types for text field detection
pub const TextFieldError = error{
    InvalidHandle,
    NotATextField,
    FailedToGetText,
    FailedToSetText,
};

/// Structure to hold information about a detected text field
pub const TextField = struct {
    /// Window handle for the text field
    handle: api.HWND,
    /// Window class name (Edit, RichEdit, etc.)
    class_name: [64]u8,
    /// Current selection start position
    selection_start: usize,
    /// Current selection end position
    selection_end: usize,
    /// Whether this is a valid text field
    is_valid: bool,
    /// Process ID of the owning application
    process_id: api.DWORD,
    /// Thread ID of the owning thread
    thread_id: api.DWORD,

    /// Initialize a new text field structure
    pub fn init() TextField {
        return TextField{
            .handle = undefined,
            .class_name = [_]u8{0} ** 64,
            .selection_start = 0,
            .selection_end = 0,
            .is_valid = false,
            .process_id = 0,
            .thread_id = 0,
        };
    }

    /// Update this text field with information from the current focused window
    pub fn detectActiveTextField(self: *TextField) !void {
        // Get the currently focused window
        const focused_window = GetFocus();
        if (focused_window == null) {
            // If no window has focus, try the foreground window instead
            const foreground_window = GetForegroundWindow();
            if (foreground_window == null) {
                return TextFieldError.InvalidHandle;
            }
            self.handle = foreground_window.?;
        } else {
            self.handle = focused_window.?;
        }

        // Get the window class name to determine if it's a text field
        const class_name_ptr: [*:0]u8 = @ptrCast(&self.class_name);
        const class_name_len = GetClassNameA(self.handle, class_name_ptr, 64);

        if (class_name_len <= 0) {
            return TextFieldError.InvalidHandle;
        }

        // Get the process and thread IDs
        var process_id: api.DWORD = undefined;
        self.thread_id = GetWindowThreadProcessId(self.handle, &process_id);
        self.process_id = process_id;

        // Check if this is a known text field class
        self.is_valid = false;
        const class_name_slice = self.class_name[0..@intCast(class_name_len)];

        for (TEXT_FIELD_CLASS_NAMES) |name| {
            if (std.mem.eql(u8, class_name_slice, name)) {
                self.is_valid = true;
                break;
            }
        }

        if (!self.is_valid) {
            return TextFieldError.NotATextField;
        }

        // Get the current selection range
        const selection = SendMessageA(self.handle, api.EM_GETSEL, 0, 0);
        self.selection_start = @intCast(selection & 0xFFFF);
        self.selection_end = @intCast((selection >> 16) & 0xFFFF);

        std.debug.print("Detected text field: {s}, selection: {}-{}\n", .{ class_name_slice, self.selection_start, self.selection_end });

        return;
    }

    /// Get the current text content from the text field
    pub fn getText(self: TextField, allocator: std.mem.Allocator) ![]u8 {
        if (!self.is_valid) {
            return TextFieldError.NotATextField;
        }

        // First, get the text length
        const text_length_result = SendMessageA(self.handle, api.WM_GETTEXTLENGTH, 0, 0);
        const text_length: usize = @intCast(text_length_result);

        if (text_length == 0) {
            return allocator.alloc(u8, 0);
        }

        // Allocate buffer for the text (plus null terminator)
        var buffer = try allocator.alloc(u8, text_length + 1);

        // Get the text content
        const ptr_value: usize = @intFromPtr(buffer.ptr);
        const lparam_value: api.LPARAM = @bitCast(ptr_value);
        const result = SendMessageA(self.handle, api.WM_GETTEXT, text_length + 1, lparam_value);

        if (result == 0) {
            allocator.free(buffer);
            return TextFieldError.FailedToGetText;
        }

        // Return the text without the null terminator
        return buffer[0..@intCast(result)];
    }

    /// Set the text content of the text field
    pub fn setText(self: TextField, text: []const u8) !void {
        if (!self.is_valid) {
            return TextFieldError.NotATextField;
        }

        // First, select all text
        _ = SendMessageA(self.handle, api.EM_SETSEL, 0, -1);

        // Then replace selection with new text
        const ptr_value: usize = @intFromPtr(text.ptr);
        const lparam_value: api.LPARAM = @bitCast(ptr_value);
        const result = SendMessageA(self.handle, api.EM_REPLACESEL, 1, // True to allow undo
            lparam_value);

        if (result == 0) {
            return TextFieldError.FailedToSetText;
        }
    }

    /// Set the selection range in the text field
    pub fn setSelection(self: TextField, start: usize, end: usize) !void {
        if (!self.is_valid) {
            return TextFieldError.NotATextField;
        }

        _ = SendMessageA(self.handle, api.EM_SETSEL, start, end);
    }
};

/// Manages text field detection and interaction across applications
pub const TextFieldManager = struct {
    /// The currently active text field
    active_field: TextField,
    /// The allocator for text operations
    allocator: std.mem.Allocator,
    /// Whether a text field is currently active
    has_active_field: bool,

    /// Initialize the text field manager
    pub fn init(allocator: std.mem.Allocator) TextFieldManager {
        return TextFieldManager{
            .active_field = TextField.init(),
            .allocator = allocator,
            .has_active_field = false,
        };
    }

    /// Detect the active text field
    pub fn detectActiveField(self: *TextFieldManager) bool {
        self.active_field.detectActiveTextField() catch {
            self.has_active_field = false;
            return false;
        };

        self.has_active_field = true;
        return true;
    }

    /// Get text from the active text field
    pub fn getActiveFieldText(self: TextFieldManager) ![]u8 {
        if (!self.has_active_field) {
            return TextFieldError.NotATextField;
        }

        return try self.active_field.getText(self.allocator);
    }

    /// Set text in the active text field
    pub fn setActiveFieldText(self: TextFieldManager, text: []const u8) !void {
        if (!self.has_active_field) {
            return TextFieldError.NotATextField;
        }

        try self.active_field.setText(text);
    }
};
