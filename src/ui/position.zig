const std = @import("std");
const sysinput = @import("root").sysinput;

const api = sysinput.win32.api;
const debug = sysinput.core.debug;

/// Get the position of the text caret or active window
pub fn getCaretPosition() api.POINT {
    var pt = api.POINT{ .x = 0, .y = 0 };

    // First try using GUI thread info which is more reliable
    const focus_hwnd = api.getFocus();
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

                // Convert to screen coordinates - properly handle the optional
                _ = api.clientToScreen(gui_info.hwndCaret.?, &pt);
                debug.debugPrint("Got caret position from GUITHREADINFO: {d},{d}\n", .{ pt.x, pt.y });
                return applyPositionOffset(pt);
            }
        }

        // If GUI thread info failed, try direct caret position
        if (api.getCaretPos(&pt) != 0) {
            // Convert from client to screen coordinates
            _ = api.clientToScreen(focus_hwnd.?, &pt);
            debug.debugPrint("Got caret position directly: {d},{d}\n", .{ pt.x, pt.y });
            return applyPositionOffset(pt);
        }

        // Try using EM_POSFROMCHAR as a fallback for Edit controls
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
            debug.debugPrint("Got caret position from selection: {d},{d}\n", .{ pt.x, pt.y });
            return applyPositionOffset(pt);
        }
    }

    // Fall back to cursor position if everything else fails
    _ = api.getCursorPos(&pt);
    debug.debugPrint("Falling back to cursor position: {d},{d}\n", .{ pt.x, pt.y });
    return applyPositionOffset(pt);
}

fn applyPositionOffset(pt: api.POINT) api.POINT {
    var result = pt;

    // Simple fixed offset
    result.y += 20;

    return result;
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
