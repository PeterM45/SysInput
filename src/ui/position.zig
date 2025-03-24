const std = @import("std");
const sysinput = @import("../sysinput.zig");

const api = sysinput.win32.api;
const debug = sysinput.core.debug;

/// Get the position of the text caret or active window
pub fn getCaretPosition() api.POINT {
    var pt = api.POINT{ .x = 0, .y = 0 };

    // Try to get caret position using GUI thread info
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

    const focus_hwnd = api.GetFocus();
    if (focus_hwnd != null) {
        const thread_id = api.GetWindowThreadProcessId(focus_hwnd.?, null);
        if (api.GetGUIThreadInfo(thread_id, &gui_info) != 0 and gui_info.hwndCaret != null) {
            // We got caret info - use it
            pt.x = gui_info.rcCaret.left;
            pt.y = gui_info.rcCaret.bottom; // Position below the caret

            // Convert from client coordinates to screen coordinates
            if (api.ClientToScreen(gui_info.hwndCaret.?, &pt) != 0) {
                debug.debugPrint("Using exact caret position: {}, {}\n", .{ pt.x, pt.y });
                return pt;
            }
        }

        // Try EM_POSFROMCHAR for edit controls
        const selection = api.SendMessageA(focus_hwnd.?, api.EM_GETSEL, 0, 0);
        const sel_u64: u64 = @bitCast(selection);
        const end_pos: u32 = @truncate((sel_u64 >> 16) & 0xFFFF);

        const pos_result = api.SendMessageA(focus_hwnd.?, api.EM_POSFROMCHAR, end_pos, 0);
        if (pos_result != 0) {
            const pos_u64: u64 = @bitCast(pos_result);
            pt.x = @intCast(@as(i32, @intFromFloat(@as(f32, @floatFromInt(pos_u64 & 0xFFFF)))));
            pt.y = @intCast(@as(i32, @intFromFloat(@as(f32, @floatFromInt((pos_u64 >> 16) & 0xFFFF)))));

            if (api.ClientToScreen(focus_hwnd.?, &pt) != 0) {
                debug.debugPrint("Using EM_POSFROMCHAR position: {}, {}\n", .{ pt.x, pt.y });
                return pt;
            }
        }
    }

    // Try to get foreground window first
    const foreground_hwnd = api.GetForegroundWindow();
    if (foreground_hwnd == null) {
        // Last resort: use cursor position
        _ = api.GetCursorPos(&pt);
        debug.debugPrint("No foreground window, using cursor position\n", .{});
        return pt;
    }

    debug.debugPrint("Found foreground window at 0x{x}\n", .{@intFromPtr(foreground_hwnd.?)});

    // First approach: Try to use cursor position if it's inside the window
    var cursor_pos: api.POINT = undefined;
    if (api.GetCursorPos(&cursor_pos) != 0) {
        // Get window rect
        var window_rect: api.RECT = undefined;
        if (api.GetWindowRect(foreground_hwnd.?, &window_rect) != 0) {
            // Check if cursor is inside window
            if (cursor_pos.x >= window_rect.left and
                cursor_pos.x <= window_rect.right and
                cursor_pos.y >= window_rect.top and
                cursor_pos.y <= window_rect.bottom)
            {
                // Position below cursor
                pt.x = cursor_pos.x;
                pt.y = cursor_pos.y + 20;
                debug.debugPrint("Using cursor position inside window: {}, {}\n", .{ pt.x, pt.y });
                return pt;
            }
        }
    }

    // Try to find controls within the window
    const edit_control = api.FindWindowExA(foreground_hwnd.?, null, "Edit\x00", null);
    if (edit_control != null) {
        var control_rect: api.RECT = undefined;
        if (api.GetWindowRect(edit_control.?, &control_rect) != 0) {
            // Position at the bottom of the control
            pt.x = control_rect.left + 10;
            pt.y = control_rect.bottom + 5;
            debug.debugPrint("Using Edit control position: {}, {}\n", .{ pt.x, pt.y });
            return pt;
        }
    }

    // Finally, position relative to foreground window
    var window_rect: api.RECT = undefined;
    if (api.GetWindowRect(foreground_hwnd.?, &window_rect) != 0) {
        // Position in the middle-left of the window
        pt.x = window_rect.left + 100;
        pt.y = window_rect.top + @divTrunc(window_rect.bottom - window_rect.top, 2);
        debug.debugPrint("Using window position: {}, {}\n", .{ pt.x, pt.y });
        return pt;
    }

    // Last resort: fixed position on screen
    pt.x = 100;
    pt.y = 100;
    debug.debugPrint("Using fixed fallback position\n", .{});
    return pt;
}

/// Calculate suggestion window size based on suggestions
pub fn calculateSuggestionWindowSize(suggestions: [][]const u8, font_height: i32, padding: i32) struct { width: i32, height: i32 } {
    const line_height = font_height + 4;
    const window_height = @as(i32, @intCast(suggestions.len)) * line_height + padding * 2;

    // Find the widest suggestion
    var max_width: i32 = 150; // Minimum width
    for (suggestions) |suggestion| {
        const width = @as(i32, @intCast(suggestion.len * 8)); // Approximate width based on character count
        if (width > max_width) {
            max_width = width;
        }
    }
    const window_width = max_width + padding * 2;

    return .{ .width = window_width, .height = window_height };
}
