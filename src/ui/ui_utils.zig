const std = @import("std");
const common = @import("../win32/common.zig");

/// Get the position of the text caret in screen coordinates
pub fn getCaretPosition() common.POINT {
    var pt = common.POINT{ .x = 0, .y = 0 };

    // Get the focus window (text field)
    const focus_hwnd = common.GetFocus();
    if (focus_hwnd == null) {
        _ = common.GetCursorPos(&pt); // Fallback to cursor position
        std.debug.print("No focus window, using cursor position\n", .{});
        return pt;
    }

    std.debug.print("Found focused window at 0x{x}\n", .{@intFromPtr(focus_hwnd.?)});

    // Method 1: Try to get position from text field bounds
    var rect: common.RECT = undefined;
    if (common.GetWindowRect(focus_hwnd.?, &rect) != 0) {
        // Position in the middle of the text field
        const midpoint_x = rect.left + @divTrunc(rect.right - rect.left, 2);
        const text_y = rect.top + 20; // Position near the top of the text field

        std.debug.print("Using text field position: {}, {}\n", .{ midpoint_x, text_y });
        return .{ .x = midpoint_x, .y = text_y };
    }

    // Last resort: use cursor position
    _ = common.GetCursorPos(&pt);
    std.debug.print("Fallback to cursor position: {}, {}\n", .{ pt.x, pt.y });
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
