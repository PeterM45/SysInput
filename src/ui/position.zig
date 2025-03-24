const std = @import("std");
const sysinput = @import("../sysinput.zig");

const api = sysinput.win32.api;
const debug = sysinput.core.debug;

/// Get the position of the text caret or active window
pub fn getCaretPosition() api.POINT {
    var pt = api.POINT{ .x = 0, .y = 0 };

    debug.debugPrint("Finding caret position...\n", .{});

    // METHOD 1: Try direct GetCaretPos Windows API
    if (api.getCaretPos(&pt) != 0) {
        // GetCaretPos returns client coordinates, so we need to convert to screen
        const focus_hwnd = api.getFocus();
        if (focus_hwnd != null) {
            if (api.clientToScreen(focus_hwnd.?, &pt) != 0) {
                debug.debugPrint("Using GetCaretPos position: {}, {}\n", .{ pt.x, pt.y });
                return pt;
            }
        }
    }

    // METHOD 2: Try to get caret position using GUI thread info
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

    const focus_hwnd = api.getFocus();
    if (focus_hwnd != null) {
        debug.debugPrint("Focus window: 0x{x}\n", .{@intFromPtr(focus_hwnd.?)});

        // Get class name for special handling
        const class_name = api.safeGetClassName(focus_hwnd) catch "";
        debug.debugPrint("Window class: {s}\n", .{class_name});

        // Try GUI thread info first
        const thread_id = api.getWindowThreadProcessId(focus_hwnd.?, null);
        const gui_info_result = api.getGUIThreadInfo(thread_id, &gui_info);

        if (gui_info_result != 0 and gui_info.hwndCaret != null) {
            // We got caret info - use it
            pt.x = gui_info.rcCaret.left;
            pt.y = gui_info.rcCaret.bottom; // Position below the caret

            // Check if the caret has reasonable coordinates
            if (pt.x != 0 or pt.y != 0) {
                // Convert from client coordinates to screen coordinates
                if (api.clientToScreen(gui_info.hwndCaret.?, &pt) != 0) {
                    debug.debugPrint("Using exact caret position: {}, {}\n", .{ pt.x, pt.y });
                    return pt;
                }
            }
        }

        const is_edit_control = isEditControlClass(class_name);

        if (is_edit_control) {
            const selection = api.sendMessage(focus_hwnd.?, api.EM_GETSEL, 0, 0);
            const sel_u64: u64 = @bitCast(selection);
            const end_pos: u32 = @truncate((sel_u64 >> 16) & 0xFFFF);

            const pos_result = api.sendMessage(focus_hwnd.?, api.EM_POSFROMCHAR, end_pos, 0);
            if (pos_result != 0) {
                const pos_u64: u64 = @bitCast(pos_result);
                pt.x = @intCast(@as(i32, @intFromFloat(@as(f32, @floatFromInt(pos_u64 & 0xFFFF)))));
                pt.y = @intCast(@as(i32, @intFromFloat(@as(f32, @floatFromInt((pos_u64 >> 16) & 0xFFFF)))));

                // Add a small offset for better positioning
                pt.y += 5;

                if (api.clientToScreen(focus_hwnd.?, &pt) != 0) {
                    debug.debugPrint("Using EM_POSFROMCHAR position: {}, {}\n", .{ pt.x, pt.y });
                    return pt;
                }
            }
        }
    }

    // Try to get foreground window if focus methods failed
    const foreground_hwnd = api.getForegroundWindow();
    if (foreground_hwnd == null) {
        // Last resort: use cursor position
        _ = api.getCursorPos(&pt);
        debug.debugPrint("No foreground window, using cursor position\n", .{});
        return pt;
    }

    debug.debugPrint("Found foreground window at 0x{x}\n", .{@intFromPtr(foreground_hwnd.?)});

    // METHOD 3: Try cursor position if it's inside the window
    var cursor_pos: api.POINT = undefined;
    if (api.getCursorPos(&cursor_pos) != 0) {
        // Get window rect
        var window_rect: api.RECT = undefined;
        if (api.getWindowRect(foreground_hwnd.?, &window_rect) != 0) {
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

    // Rest of original function...
    const edit_control = api.findWindowEx(foreground_hwnd.?, null, "Edit\x00", null);
    if (edit_control != null) {
        var control_rect: api.RECT = undefined;
        if (api.getWindowRect(edit_control.?, &control_rect) != 0) {
            // Position at the bottom of the control
            pt.x = control_rect.left + 10;
            pt.y = control_rect.bottom + 5;
            debug.debugPrint("Using Edit control position: {}, {}\n", .{ pt.x, pt.y });
            return pt;
        }
    }

    // Finally, position relative to foreground window
    var window_rect: api.RECT = undefined;
    if (api.getWindowRect(foreground_hwnd.?, &window_rect) != 0) {
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

/// Check if a window class is an edit control
fn isEditControlClass(class_name: []const u8) bool {
    for (sysinput.input.text_field.TEXT_FIELD_CLASS_NAMES) |edit_class| {
        if (std.mem.eql(u8, class_name, edit_class)) {
            return true;
        }
    }
    return false;
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
