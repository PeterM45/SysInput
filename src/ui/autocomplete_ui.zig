const std = @import("std");
const common = @import("../win32/common.zig");

/// UI constants
const SUGGESTION_HEIGHT = 24;
const SUGGESTION_PADDING = 4;
const MAX_VISIBLE_SUGGESTIONS = 8;
const BG_COLOR = 0x00FFFFFF; // White background
const HIGHLIGHT_COLOR = 0x00E0E0FF; // Light blue for selected item
const TEXT_COLOR = 0x00000000; // Black text
const BORDER_COLOR = 0x00C0C0C0; // Light gray border

/// Simple borderless layered window for suggestions
const WINDOW_CLASS_NAME = "SysInputIntegratedSuggestions";
const WINDOW_STYLE = common.WS_POPUP; // Just a popup without borders or caption
const WINDOW_EX_STYLE = common.WS_EX_TOPMOST | common.WS_EX_LAYERED | common.WS_EX_TRANSPARENT | common.WS_EX_NOACTIVATE;

/// Windows API functions
extern "user32" fn CreateWindowExA(
    dwExStyle: common.DWORD,
    lpClassName: [*:0]const u8,
    lpWindowName: [*:0]const u8,
    dwStyle: common.DWORD,
    x: c_int,
    y: c_int,
    nWidth: c_int,
    nHeight: c_int,
    hWndParent: ?common.HWND,
    hMenu: ?common.HANDLE,
    hInstance: common.HINSTANCE,
    lpParam: ?*anyopaque,
) callconv(.C) ?common.HWND;

extern "user32" fn ShowWindow(
    hWnd: common.HWND,
    nCmdShow: c_int,
) callconv(.C) common.BOOL;

extern "user32" fn UpdateWindow(
    hWnd: common.HWND,
) callconv(.C) common.BOOL;

extern "user32" fn DestroyWindow(
    hWnd: common.HWND,
) callconv(.C) common.BOOL;

extern "user32" fn RegisterClassExA(
    lpWndClass: *const common.WNDCLASSEX,
) callconv(.C) common.ATOM;

extern "user32" fn DefWindowProcA(
    hWnd: common.HWND,
    Msg: common.UINT,
    wParam: common.WPARAM,
    lParam: common.LPARAM,
) callconv(.C) common.LRESULT;

extern "user32" fn SetWindowPos(
    hWnd: common.HWND,
    hWndInsertAfter: ?common.HWND,
    X: c_int,
    Y: c_int,
    cx: c_int,
    cy: c_int,
    uFlags: common.UINT,
) callconv(.C) common.BOOL;

extern "user32" fn SetLayeredWindowAttributes(
    hwnd: common.HWND,
    crKey: common.COLORREF,
    bAlpha: u8,
    dwFlags: common.DWORD,
) callconv(.C) common.BOOL;

extern "user32" fn GetWindowRect(
    hWnd: common.HWND,
    lpRect: *common.RECT,
) callconv(.C) common.BOOL;

extern "user32" fn SetWindowLongA(
    hWnd: common.HWND,
    nIndex: c_int,
    dwNewLong: common.LONG,
) callconv(.C) common.LONG;

extern "user32" fn BeginPaint(
    hWnd: common.HWND,
    lpPaint: *common.PAINTSTRUCT,
) callconv(.C) ?common.HDC;

extern "user32" fn EndPaint(
    hWnd: common.HWND,
    lpPaint: *const common.PAINTSTRUCT,
) callconv(.C) common.BOOL;

extern "gdi32" fn CreateSolidBrush(
    color: common.COLORREF,
) callconv(.C) ?common.HANDLE;

extern "gdi32" fn DeleteObject(
    ho: common.HANDLE,
) callconv(.C) common.BOOL;

extern "gdi32" fn SelectObject(
    hdc: common.HDC,
    h: common.HANDLE,
) callconv(.C) ?common.HANDLE;

extern "gdi32" fn Rectangle(
    hdc: common.HDC,
    left: c_int,
    top: c_int,
    right: c_int,
    bottom: c_int,
) callconv(.C) common.BOOL;

extern "gdi32" fn FillRect(
    hdc: common.HDC,
    lprc: *const common.RECT,
    hbr: common.HANDLE,
) callconv(.C) c_int;

extern "gdi32" fn CreatePen(
    iStyle: c_int,
    cWidth: c_int,
    color: common.COLORREF,
) callconv(.C) ?common.HANDLE;

extern "gdi32" fn TextOutA(
    hdc: common.HDC,
    x: c_int,
    y: c_int,
    lpString: [*:0]const u8,
    c: c_int,
) callconv(.C) common.BOOL;

extern "gdi32" fn SetBkColor(
    hdc: common.HDC,
    color: common.COLORREF,
) callconv(.C) common.COLORREF;

extern "gdi32" fn SetTextColor(
    hdc: common.HDC,
    color: common.COLORREF,
) callconv(.C) common.COLORREF;

/// Global state for window procedure
var g_ui_state: ?*AutocompleteUI = null;

/// Autocomplete UI manager (simplified version)
pub const AutocompleteUI = struct {
    /// Window handle for the suggestion popup
    window: ?common.HWND,
    /// Module instance handle
    instance: common.HINSTANCE,
    /// Current suggestions to display (owned externally)
    suggestions: [][]const u8,
    /// Selected suggestion index (-1 if none)
    selected_index: i32,
    /// Allocator for UI operations
    allocator: std.mem.Allocator,
    /// Whether the UI is currently visible
    is_visible: bool,
    /// Callback function for handling selection
    selection_callback: ?*const fn ([]const u8) void,

    /// Initialize the UI system
    pub fn init(allocator: std.mem.Allocator, instance: common.HINSTANCE) !AutocompleteUI {
        var ui = AutocompleteUI{
            .window = null,
            .instance = instance,
            .suggestions = &[_][]const u8{},
            .selected_index = -1,
            .allocator = allocator,
            .is_visible = false,
            .selection_callback = null,
        };

        // Register window class
        const wc = common.WNDCLASSEX{
            .cbSize = @sizeOf(common.WNDCLASSEX),
            .style = 0,
            .lpfnWndProc = windowProc,
            .cbClsExtra = 0,
            .cbWndExtra = 0,
            .hInstance = instance,
            .hIcon = null,
            .hCursor = null,
            .hbrBackground = @ptrFromInt(6), // COLOR_WINDOW + 1
            .lpszMenuName = null,
            .lpszClassName = WINDOW_CLASS_NAME,
            .hIconSm = null,
        };

        // Store global reference for window procedure
        g_ui_state = &ui;

        if (RegisterClassExA(&wc) == 0) {
            std.debug.print("Failed to register suggestion window class\n", .{});
            return error.WindowRegistrationFailed;
        }

        return ui;
    }

    /// Show suggestions at the given coordinates
    pub fn showSuggestions(self: *AutocompleteUI, suggestions: [][]const u8, x: i32, y: i32) !void {
        self.suggestions = suggestions;
        self.selected_index = 0; // Select first item by default

        // Skip showing if no suggestions
        if (suggestions.len == 0) {
            self.hideSuggestions();
            return;
        }

        // Calculate window dimensions
        var max_width: i32 = 150; // Minimum width
        for (suggestions) |suggestion| {
            // Rough estimation of text width (characters * average width)
            const width = @as(i32, @intCast(suggestion.len * 7));
            if (width > max_width) {
                max_width = width;
            }
        }

        const window_width = max_width + SUGGESTION_PADDING * 2;
        const visible_suggestions = @min(suggestions.len, MAX_VISIBLE_SUGGESTIONS);
        const window_height = @as(i32, @intCast(visible_suggestions)) * SUGGESTION_HEIGHT + SUGGESTION_PADDING;

        // Create or update window
        if (self.window) |window| {
            _ = SetWindowPos(
                window,
                common.HWND_TOPMOST,
                x,
                y,
                window_width,
                window_height,
                0,
            );
            _ = ShowWindow(window, 1); // SW_SHOW
            _ = UpdateWindow(window);
        } else {
            self.window = CreateWindowExA(
                WINDOW_EX_STYLE,
                WINDOW_CLASS_NAME,
                "", // No title
                WINDOW_STYLE,
                x,
                y,
                window_width,
                window_height,
                null,
                null,
                self.instance,
                null,
            );

            if (self.window == null) {
                std.debug.print("Failed to create suggestion overlay\n", .{});
                return error.WindowCreationFailed;
            }

            // Set window transparency (semi-transparent)
            _ = SetLayeredWindowAttributes(self.window.?, 0, 240, common.LWA_ALPHA);

            _ = ShowWindow(self.window.?, 1); // SW_SHOW
            _ = UpdateWindow(self.window.?);
        }

        self.is_visible = true;
    }

    /// Hide the suggestion UI
    pub fn hideSuggestions(self: *AutocompleteUI) void {
        if (self.window) |window| {
            _ = ShowWindow(window, 0); // SW_HIDE
        }
        self.is_visible = false;
    }

    /// Set the callback for suggestion selection
    pub fn setSelectionCallback(self: *AutocompleteUI, callback: *const fn ([]const u8) void) void {
        self.selection_callback = callback;
    }

    /// Select a suggestion by index
    pub fn selectSuggestion(self: *AutocompleteUI, index: i32) void {
        if (index >= 0 and index < self.suggestions.len) {
            self.selected_index = index;
            if (self.window) |window| {
                // Force redraw
                var rect: common.RECT = undefined;
                _ = GetWindowRect(window, &rect);
                _ = SetWindowPos(
                    window,
                    common.HWND_TOPMOST,
                    rect.left,
                    rect.top,
                    rect.right - rect.left,
                    rect.bottom - rect.top,
                    0,
                );
                _ = UpdateWindow(window);
            }
        }
    }

    /// Clean up resources
    pub fn deinit(self: *AutocompleteUI) void {
        if (self.window) |window| {
            _ = DestroyWindow(window);
            self.window = null;
        }
    }
};

/// Window procedure for the suggestion window
fn windowProc(hWnd: common.HWND, uMsg: common.UINT, wParam: common.WPARAM, lParam: common.LPARAM) callconv(.C) common.LRESULT {
    if (g_ui_state) |ui| {
        switch (uMsg) {
            common.WM_PAINT => {
                var ps: common.PAINTSTRUCT = undefined;
                const hdc = BeginPaint(hWnd, &ps) orelse return 0;
                defer _ = EndPaint(hWnd, &ps);

                // Create a pen for the border
                const pen = CreatePen(common.PS_SOLID, 1, BORDER_COLOR) orelse return 0;
                defer _ = DeleteObject(pen);

                const old_pen = SelectObject(hdc, pen);
                defer {
                    if (old_pen) |old| {
                        _ = SelectObject(hdc, old);
                    }
                }

                // Draw the suggestions with subtle styling
                var y_pos: i32 = 0;
                for (ui.suggestions, 0..) |suggestion, i| {
                    const index = @as(i32, @intCast(i));
                    const is_selected = ui.selected_index == index;

                    // Rectangle for this suggestion
                    const rect = common.RECT{
                        .left = 0,
                        .top = y_pos,
                        .right = ps.rcPaint.right,
                        .bottom = y_pos + SUGGESTION_HEIGHT,
                    };

                    // Fill background
                    const bg_brush = if (is_selected) CreateSolidBrush(HIGHLIGHT_COLOR) else CreateSolidBrush(BG_COLOR);
                    defer {
                        if (bg_brush) |brush| {
                            _ = DeleteObject(brush);
                        }
                    }
                    _ = FillRect(hdc, &rect, bg_brush.?);

                    // Draw text
                    _ = SetBkColor(hdc, if (is_selected) HIGHLIGHT_COLOR else BG_COLOR);
                    _ = SetTextColor(hdc, TEXT_COLOR);

                    // Create null-terminated string
                    const c_str = ui.allocator.dupeZ(u8, suggestion) catch {
                        std.debug.print("Failed to allocate string\n", .{});
                        continue;
                    };
                    defer ui.allocator.free(c_str);

                    _ = TextOutA(hdc, SUGGESTION_PADDING, y_pos + 4, c_str, @intCast(suggestion.len));

                    // Draw a subtle bottom border for each item except the last
                    if (i < ui.suggestions.len - 1) {
                        _ = Rectangle(hdc, 0, y_pos + SUGGESTION_HEIGHT - 1, ps.rcPaint.right, y_pos + SUGGESTION_HEIGHT);
                    }

                    y_pos += SUGGESTION_HEIGHT;
                }

                // Draw outer border
                _ = Rectangle(hdc, 0, 0, ps.rcPaint.right, ps.rcPaint.bottom);

                return 0;
            },
            common.WM_LBUTTONDOWN => {
                // We only need y_pos here, x_pos is not used
                const y_pos = @as(i16, @truncate(lParam >> 16));

                // Determine which suggestion was clicked
                const index = @divFloor(y_pos, SUGGESTION_HEIGHT);
                if (index >= 0 and index < ui.suggestions.len) {
                    ui.selected_index = index;

                    // Execute the selection if a callback is set
                    if (ui.selection_callback) |callback| {
                        if (ui.selected_index >= 0) {
                            callback(ui.suggestions[@intCast(ui.selected_index)]);
                            ui.hideSuggestions();
                        }
                    }
                }

                return 0;
            },
            common.WM_DESTROY => {
                ui.window = null;
                ui.is_visible = false;
                return 0;
            },
            else => {
                return DefWindowProcA(hWnd, uMsg, wParam, lParam);
            },
        }
    }

    return DefWindowProcA(hWnd, uMsg, wParam, lParam);
}
