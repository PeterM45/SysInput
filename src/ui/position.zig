const std = @import("std");
const sysinput = @import("root").sysinput;

const api = sysinput.win32.api;
const debug = sysinput.core.debug;
const config = sysinput.core.config;

/// Position cache to avoid frequent expensive API calls
const PositionCache = struct {
    /// Cached position
    position: api.POINT,
    /// Timestamp when position was cached
    timestamp: i64,
    /// Window handle this position is for
    window_handle: ?api.HWND,
    /// Whether the cache is valid
    valid: bool,

    pub fn init() PositionCache {
        return .{
            .position = .{ .x = 0, .y = 0 },
            .timestamp = 0,
            .window_handle = null,
            .valid = false,
        };
    }

    pub fn isValid(self: *const PositionCache, current_hwnd: ?api.HWND) bool {
        // If caching is disabled in config, always return false
        if (!config.PERFORMANCE.USE_POSITION_CACHE) return false;

        if (!self.valid) return false;

        // Cache is invalid if the window changed
        if (self.window_handle != current_hwnd) return false;

        // Check if cache has expired
        const current_time = std.time.milliTimestamp();
        return (current_time - self.timestamp) < config.PERFORMANCE.POSITION_CACHE_LIFETIME_MS;
    }

    pub fn update(self: *PositionCache, position: api.POINT, hwnd: ?api.HWND) void {
        self.position = position;
        self.timestamp = std.time.milliTimestamp();
        self.window_handle = hwnd;
        self.valid = true;
    }

    pub fn invalidate(self: *PositionCache) void {
        self.valid = false;
    }
};

/// Global position cache instance
var g_position_cache = PositionCache.init();

/// Gets the DPI scaling factor for the given window
fn getDpiScaling(hwnd: ?api.HWND) f32 {
    // Get DC for the window or screen
    const hdc = if (hwnd != null) api.GetDC(hwnd.?) else api.GetDC(null);
    if (hdc == null) return 1.0;
    defer _ = api.ReleaseDC(if (hwnd != null) hwnd.? else null, hdc.?);

    // Get logical DPI and use the config's BASE_DPI value
    const dpi = api.GetDeviceCaps(hdc.?, api.LOGPIXELSY);
    return @as(f32, @floatFromInt(dpi)) / config.UI.BASE_DPI;
}

/// Get the position of the text caret or active window
pub fn getCaretPosition() api.POINT {
    // Get current focused window for cache checking
    const focus_hwnd = api.getFocus();

    // Try the cache first
    if (g_position_cache.isValid(focus_hwnd)) {
        debug.debugPrint("Using cached caret position: {d},{d}\n", .{ g_position_cache.position.x, g_position_cache.position.y });
        return g_position_cache.position;
    }

    var pt = api.POINT{ .x = 0, .y = 0 };

    // Track which method succeeded for debugging
    var method_used: u8 = 0;

    // Method 1: GUI thread info (most reliable)
    if (focus_hwnd != null) {
        // Get thread ID for the window
        const thread_id = api.getWindowThreadProcessId(focus_hwnd.?, null);

        // Initialize GUITHREADINFO structure
        var gui_info = api.GUITHREADINFO{
            .cbSize = @sizeOf(api.GUITHREADINFO),
            .flags = 0,
            .hwndActive = null,
            .hwndFocus = null,
            .hwndCapture = null,
            .hwndMenuOwner = null,
            .hwndMoveSize = null,
            .hwndCaret = null,
            .rcCaret = api.RECT{ .left = 0, .top = 0, .right = 0, .bottom = 0 },
        };

        // Try to get GUI thread info
        if (api.getGUIThreadInfo(thread_id, &gui_info) != 0) {
            if (gui_info.hwndCaret != null) {
                // Use caret rectangle from GUI thread info
                pt.x = gui_info.rcCaret.left;
                pt.y = gui_info.rcCaret.bottom; // Use bottom for better positioning

                // Convert to screen coordinates
                _ = api.clientToScreen(gui_info.hwndCaret.?, &pt);
                method_used = 1;
                debug.debugPrint("Got caret position from GUITHREADINFO: {d},{d}\n", .{ pt.x, pt.y });

                // Cache and return the result
                g_position_cache.update(pt, focus_hwnd);
                return applyPositionOffset(pt, focus_hwnd);
            }
        }

        // Method 2: Direct caret position
        if (api.getCaretPos(&pt) != 0) {
            // Convert from client to screen coordinates
            _ = api.clientToScreen(focus_hwnd.?, &pt);
            method_used = 2;
            debug.debugPrint("Got caret position directly: {d},{d}\n", .{ pt.x, pt.y });

            // Cache and return the result
            g_position_cache.update(pt, focus_hwnd);
            return applyPositionOffset(pt, focus_hwnd);
        }

        // Method 3: EM_POSFROMCHAR as a fallback for Edit controls
        const selection = api.sendMessage(focus_hwnd.?, api.EM_GETSEL, 0, 0);
        const sel_u64: u64 = @bitCast(selection);
        const sel_end: u32 = @truncate((sel_u64 >> 16) & 0xFFFF);

        // Get position for that character
        const char_pos = api.sendMessage(focus_hwnd.?, api.EM_POSFROMCHAR, sel_end, 0);
        if (char_pos != -1) {
            // Extract the x,y values directly using bit masking
            pt.x = @intCast(char_pos & 0xFFFF);
            pt.y = @intCast((char_pos >> 16) & 0xFFFF);
            _ = api.clientToScreen(focus_hwnd.?, &pt);
            method_used = 3;
            debug.debugPrint("Got caret position from selection: {d},{d}\n", .{ pt.x, pt.y });

            // Cache and return the result
            g_position_cache.update(pt, focus_hwnd);
            return applyPositionOffset(pt, focus_hwnd);
        }
    }

    // Method 4: Fall back to cursor position if everything else fails
    _ = api.getCursorPos(&pt);
    method_used = 4;
    debug.debugPrint("Falling back to cursor position: {d},{d}\n", .{ pt.x, pt.y });

    // Cache this result too
    g_position_cache.update(pt, focus_hwnd);
    return applyPositionOffset(pt, focus_hwnd);
}

/// Apply appropriate offset based on DPI and window type
fn applyPositionOffset(pt: api.POINT, hwnd: ?api.HWND) api.POINT {
    var result = pt;

    // Get DPI scaling
    const dpi_scale = getDpiScaling(hwnd);

    // Apply scaled offset based on DPI using config value
    const base_offset = config.UI.CARET_VERTICAL_OFFSET;
    const scaled_offset = @as(i32, @intFromFloat(@as(f32, @floatFromInt(base_offset)) * dpi_scale));
    result.y += scaled_offset;

    // Apply additional adjustments based on window class if needed
    if (hwnd != null) {
        var class_name: [64]u8 = undefined;
        const class_name_len = api.getClassName(hwnd, @ptrCast(&class_name), 64);

        if (class_name_len > 0) {
            const class_slice = class_name[0..@intCast(class_name_len)];

            // Adjust for specific window classes using config values
            if (std.mem.eql(u8, class_slice, "Edit")) {
                // Standard edit controls
                result.y += config.WINDOW_CLASS_ADJUSTMENTS.EDIT_CONTROL_OFFSET;
            } else if (std.mem.startsWith(u8, class_slice, "RichEdit")) {
                // Rich edit controls
                result.y += config.WINDOW_CLASS_ADJUSTMENTS.RICHEDIT_CONTROL_OFFSET;
            }
        }
    }

    // Apply adjustments to keep popup on screen
    const screen_width = api.getSystemMetrics(api.SM_CXSCREEN);
    const screen_height = api.getSystemMetrics(api.SM_CYSCREEN);

    // Use config values for popup dimensions
    const popup_width = config.UI.DEFAULT_POPUP_WIDTH;
    const popup_height = config.UI.DEFAULT_POPUP_HEIGHT;
    const edge_padding = config.UI.SCREEN_EDGE_PADDING;

    // Make sure popup will be visible on screen
    if (result.x + popup_width > screen_width) {
        result.x = screen_width - popup_width - edge_padding;
    }
    if (result.x < edge_padding) result.x = edge_padding;

    if (result.y + popup_height > screen_height) {
        // Move above if no room below
        result.y = pt.y - popup_height - edge_padding;
    }
    if (result.y < edge_padding) result.y = edge_padding;

    return result;
}

/// Force invalidation of position cache - call when window focus changes
pub fn invalidatePositionCache() void {
    g_position_cache.invalidate();
}

/// Calculate suggestion window size based on suggestions and DPI
pub fn calculateSuggestionWindowSize(suggestions: [][]const u8, font_height: i32, padding: i32) struct { width: i32, height: i32 } {
    const focus_hwnd = api.getFocus();
    const dpi_scale = getDpiScaling(focus_hwnd);

    // Scale font height and padding
    const scaled_font_height = @as(i32, @intFromFloat(@as(f32, @floatFromInt(font_height)) * dpi_scale));
    const scaled_padding = @as(i32, @intFromFloat(@as(f32, @floatFromInt(padding)) * dpi_scale));

    const line_height = scaled_font_height + 4;
    const window_height = @as(i32, @intCast(suggestions.len)) * line_height + scaled_padding * 2;

    // Calculate window width more accurately using config for character width ratio
    var max_width: i32 = config.UI.DEFAULT_POPUP_WIDTH / 2; // Minimum width (half of default)
    for (suggestions) |suggestion| {
        // Approximate width based on character count and font size using config ratio
        const avg_char_width = @as(i32, @intFromFloat(@as(f32, @floatFromInt(scaled_font_height)) * config.UI.AVG_CHAR_WIDTH_RATIO));
        const width = @as(i32, @intCast(suggestion.len)) * avg_char_width + scaled_padding * 2;
        if (width > max_width) {
            max_width = width;
        }
    }

    // Add minimum padding
    const window_width = max_width + scaled_padding * 2;

    return .{ .width = window_width, .height = window_height };
}
