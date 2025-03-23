const std = @import("std");
const common = @import("../win32/common.zig");

/// Get the position of the text caret or active window
pub fn getCaretPosition() common.POINT {
    var pt = common.POINT{ .x = 0, .y = 0 };

    // Try to get foreground window first
    const foreground_hwnd = common.GetForegroundWindow();
    if (foreground_hwnd == null) {
        // Last resort: use cursor position
        _ = common.GetCursorPos(&pt);
        std.debug.print("No foreground window, using cursor position\n", .{});
        return pt;
    }

    std.debug.print("Found foreground window at 0x{x}\n", .{@intFromPtr(foreground_hwnd.?)});

    // First approach: Try to use cursor position if it's inside the window
    var cursor_pos: common.POINT = undefined;
    if (common.GetCursorPos(&cursor_pos) != 0) {
        // Get window rect
        var window_rect: common.RECT = undefined;
        if (common.GetWindowRect(foreground_hwnd.?, &window_rect) != 0) {
            // Check if cursor is inside window
            if (cursor_pos.x >= window_rect.left and
                cursor_pos.x <= window_rect.right and
                cursor_pos.y >= window_rect.top and
                cursor_pos.y <= window_rect.bottom)
            {
                // Position below cursor
                pt.x = cursor_pos.x;
                pt.y = cursor_pos.y + 20;
                std.debug.print("Using cursor position inside window: {}, {}\n", .{ pt.x, pt.y });
                return pt;
            }
        }
    }

    // Try to find controls within the window
    const edit_control = common.FindWindowExA(foreground_hwnd.?, null, "Edit\x00", null);
    if (edit_control != null) {
        var control_rect: common.RECT = undefined;
        if (common.GetWindowRect(edit_control.?, &control_rect) != 0) {
            // Position at the bottom of the control
            pt.x = control_rect.left + 10;
            pt.y = control_rect.bottom + 5;
            std.debug.print("Using Edit control position: {}, {}\n", .{ pt.x, pt.y });
            return pt;
        }
    }

    // Finally, position relative to foreground window
    var window_rect: common.RECT = undefined;
    if (common.GetWindowRect(foreground_hwnd.?, &window_rect) != 0) {
        // Position in the middle-left of the window
        pt.x = window_rect.left + 100;
        pt.y = window_rect.top + @divTrunc(window_rect.bottom - window_rect.top, 2);
        std.debug.print("Using window position: {}, {}\n", .{ pt.x, pt.y });
        return pt;
    }

    // Last resort: fixed position on screen
    pt.x = 100;
    pt.y = 100;
    std.debug.print("Using fixed fallback position\n", .{});
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
