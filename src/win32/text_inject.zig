const std = @import("std");
const sysinput = @import("../sysinput.zig");

const api = sysinput.win32.api;
const debug = sysinput.core.debug;

/// Insert text as a selected block using multiple approaches
/// Returns true if successful
pub fn insertTextAsSelection(hwnd: api.HWND, text: []const u8) bool {
    debug.debugPrint("Inserting text as selection: '{s}'\n", .{text});

    // Skip if no text to insert
    if (text.len == 0) {
        debug.debugPrint("No text to insert\n", .{});
        return false;
    }

    // Approach 1: Direct message-based insertion
    if (tryDirectInsertion(hwnd, text)) {
        debug.debugPrint("Direct insertion succeeded\n", .{});
        return true;
    }

    // Approach 2: Try clipboard-based approach
    if (tryClipboardInsertion(hwnd, text)) {
        debug.debugPrint("Clipboard insertion succeeded\n", .{});
        return true;
    }

    // Approach 3: Simulate typing of each character
    if (trySimulatedTyping(hwnd, text)) {
        debug.debugPrint("Simulated typing succeeded\n", .{});
        return true;
    }

    debug.debugPrint("All insertion methods failed\n", .{});
    return false;
}

/// Try direct Windows message-based insertion
fn tryDirectInsertion(hwnd: api.HWND, text: []const u8) bool {
    // Create null-terminated text
    const buffer = std.heap.page_allocator.allocSentinel(u8, text.len, 0) catch {
        debug.debugPrint("Failed to allocate buffer for text insertion\n", .{});
        return false;
    };
    defer std.heap.page_allocator.free(buffer);

    // Copy the text to the buffer
    @memcpy(buffer, text);

    // Debug: Check selection before insert
    const before_sel = api.SendMessageA(hwnd, api.EM_GETSEL, 0, 0);
    const before_u64: u64 = @bitCast(before_sel);
    const before_start: u32 = @truncate(before_u64 & 0xFFFF);
    const before_end: u32 = @truncate((before_u64 >> 16) & 0xFFFF);
    debug.debugPrint("Selection before insert: {d}-{d}\n", .{ before_start, before_end });

    // Insert the text using EM_REPLACESEL
    const insert_result = api.SendMessageA(hwnd, api.EM_REPLACESEL, 1, // True to allow undo
        @as(api.LPARAM, @intCast(@intFromPtr(buffer.ptr))));

    // Check if successful
    if (insert_result == 0) {
        debug.debugPrint("EM_REPLACESEL failed\n", .{});
        return false;
    }

    // Verify the insertion worked by checking selection
    const after_sel = api.SendMessageA(hwnd, api.EM_GETSEL, 0, 0);
    const after_u64: u64 = @bitCast(after_sel);
    const after_start: u32 = @truncate(after_u64 & 0xFFFF);
    const after_end: u32 = @truncate((after_u64 >> 16) & 0xFFFF);

    debug.debugPrint("Selection after insert: {d}-{d}\n", .{ after_start, after_end });

    // If selection didn't change, insertion likely failed
    if (before_end == after_end) {
        debug.debugPrint("Selection didn't change, insertion may have failed\n", .{});
        return false;
    }

    return true;
}

/// Try clipboard-based insertion
fn tryClipboardInsertion(hwnd: api.HWND, text: []const u8) bool {
    // Save original clipboard contents
    var original_clipboard_text: ?[]u8 = null;
    defer {
        if (original_clipboard_text) |txt| {
            std.heap.page_allocator.free(txt);
        }
    }

    // Try to save original clipboard contents
    if (api.OpenClipboard(null) != 0) {
        const original_handle = api.GetClipboardData(api.CF_TEXT);
        if (original_handle != null) {
            const data_ptr = api.GlobalLock(original_handle.?);
            if (data_ptr != null) {
                const str_len = api.lstrlenA(data_ptr);
                if (str_len > 0) {
                    const u_str_len: usize = @intCast(str_len);
                    original_clipboard_text = std.heap.page_allocator.alloc(u8, u_str_len + 1) catch null;
                    if (original_clipboard_text) |buffer| {
                        std.mem.copyForwards(u8, buffer, @as([*]u8, @ptrCast(data_ptr))[0..u_str_len]);
                        buffer[u_str_len] = 0; // Null terminate
                    }
                }
                _ = api.GlobalUnlock(original_handle.?);
            }
        }
        _ = api.CloseClipboard();
    }

    // Prepare to set clipboard with our text
    if (api.OpenClipboard(null) != 0) {
        _ = api.EmptyClipboard();

        // Allocate global memory for the text
        const handle = api.GlobalAlloc(api.GMEM_MOVEABLE, text.len + 1);
        if (handle != null) {
            const data_ptr = api.GlobalLock(handle.?);
            if (data_ptr != null) {
                // Copy text to global memory
                @memcpy(@as([*]u8, @ptrCast(data_ptr))[0..text.len], text);
                @as([*]u8, @ptrCast(data_ptr))[text.len] = 0; // Null terminate
                _ = api.GlobalUnlock(handle.?);

                // Set clipboard data
                _ = api.SetClipboardData(api.CF_TEXT, handle);
            }
        }

        _ = api.CloseClipboard();

        // Send paste command to the window (Ctrl+V)
        _ = api.SendMessageA(hwnd, api.WM_PASTE, 0, 0);

        // Wait a bit for paste to complete
        api.Sleep(50);

        // Restore original clipboard if we had saved it
        if (original_clipboard_text) |orig_text| {
            if (api.OpenClipboard(null) != 0) {
                _ = api.EmptyClipboard();

                const restore_handle = api.GlobalAlloc(api.GMEM_MOVEABLE, orig_text.len);
                if (restore_handle != null) {
                    const restore_ptr = api.GlobalLock(restore_handle.?);
                    if (restore_ptr != null) {
                        @memcpy(@as([*]u8, @ptrCast(restore_ptr))[0 .. orig_text.len - 1], orig_text[0 .. orig_text.len - 1]);
                        @as([*]u8, @ptrCast(restore_ptr))[orig_text.len - 1] = 0; // Null terminate
                        _ = api.GlobalUnlock(restore_handle.?);

                        _ = api.SetClipboardData(api.CF_TEXT, restore_handle);
                    }
                }

                _ = api.CloseClipboard();
            }
        }

        return true;
    }

    return false;
}

/// Try simulated typing
fn trySimulatedTyping(hwnd: api.HWND, text: []const u8) bool {
    // Bring window to front to ensure it receives input
    _ = api.SetForegroundWindow(hwnd);

    // Give the window time to process
    api.Sleep(50);

    // Send each character as a key press
    for (text) |c| {
        // Send character using WM_CHAR
        _ = api.SendMessageA(hwnd, api.WM_CHAR, @as(api.WPARAM, c), 0);

        // Small delay between keystrokes for reliability
        api.Sleep(5);
    }

    return true;
}

/// Try to apply completion using direct text replacement methods
/// Returns true if successful
pub fn tryDirectCompletion(partial_word: []const u8, suggestion: []const u8) bool {
    // Only proceed if the suggestion starts with the partial word
    if (partial_word.len == 0 or !std.mem.startsWith(u8, suggestion, partial_word)) {
        return false;
    }

    // Get the active window and control
    const hwnd = api.GetForegroundWindow();
    if (hwnd == null) return false;

    // Get the control with focus (usually the text field)
    const focus_hwnd = api.GetFocus();
    if (focus_hwnd == null) return false;

    debug.debugPrint("Trying direct completion: '{s}' -> '{s}'\n", .{ partial_word, suggestion });

    // Try to get selection/position in text field using standard approach
    const selection_result = api.SendMessageA(focus_hwnd.?, api.EM_GETSEL, 0, 0);

    // Extract start and end positions from the result
    const result_u64: u64 = @bitCast(selection_result);
    const start: api.DWORD = @truncate(result_u64 & 0xFFFF);
    const end: api.DWORD = @truncate((result_u64 >> 16) & 0xFFFF);

    debug.debugPrint("Selection: {d}-{d}\n", .{ start, end });

    // If we have a valid selection position
    if (start != 0 or end != 0) {
        // Calculate what part of the word we need to add
        const completion = suggestion[partial_word.len..];

        // First, position the cursor at the end of the partial word
        _ = api.SendMessageA(focus_hwnd.?, api.EM_SETSEL, end, end);

        // Insert the completion text as a selected block
        return insertTextAsSelection(focus_hwnd.?, completion);
    }

    return false;
}

/// Try to apply completion using text selection approach
/// Returns true if successful
pub fn trySelectionCompletion(partial_word: []const u8, suggestion: []const u8) bool {
    // Only proceed if the suggestion starts with the partial word
    if (partial_word.len == 0 or !std.mem.startsWith(u8, suggestion, partial_word)) {
        return false;
    }

    // Get the active window and control
    const hwnd = api.GetForegroundWindow();
    if (hwnd == null) return false;

    // Get the control with focus (usually the text field)
    const focus_hwnd = api.GetFocus();
    if (focus_hwnd == null) return false;

    debug.debugPrint("Trying selection completion: '{s}' -> '{s}'\n", .{ partial_word, suggestion });

    // Try to get text length in the control
    const text_length = api.SendMessageA(focus_hwnd.?, api.WM_GETTEXTLENGTH, 0, 0);
    if (text_length <= 0) return false;

    // Calculate what part of the word we need to add
    const completion = suggestion[partial_word.len..];

    // For selection-based completion, we attempt to:
    // 1. Set the cursor at the current position
    // 2. Insert the completion text
    // This method may work for controls that don't support EM_GETSEL/EM_SETSEL properly

    // Get the current caret position (usually at the end of the partial word)
    const current_pos = api.SendMessageA(focus_hwnd.?, api.EM_GETSEL, 0, 0);
    // Extract high word (end position)
    const high_word: u32 = @intCast(@as(u64, @bitCast(current_pos)) >> 16);
    const caret_pos: api.DWORD = high_word & 0xFFFF;

    // Position the cursor and insert the completion
    _ = api.SendMessageA(focus_hwnd.?, api.EM_SETSEL, caret_pos, caret_pos);

    // Try to insert the completion
    return insertTextAsSelection(focus_hwnd.?, completion);
}

// Add clipboard handling
pub fn insertViaClipboard(hwnd: ?api.HWND, text: []const u8) bool {
    const target = hwnd orelse {
        debug.debugPrint("Clipboard insertion failed: null window handle\n", .{});
        return false;
    };

    // Save original clipboard contents
    var original_clipboard_text: ?[]u8 = null;
    defer {
        if (original_clipboard_text) |txt| {
            std.heap.page_allocator.free(txt);
        }
    }

    // Try to save original clipboard contents
    if (api.OpenClipboard(null) != 0) {
        const original_handle = api.GetClipboardData(api.CF_TEXT);
        if (original_handle != null) {
            const data_ptr = api.GlobalLock(original_handle.?);
            if (data_ptr != null) {
                const str_len = api.lstrlenA(data_ptr);
                if (str_len > 0) {
                    const u_str_len: usize = @intCast(str_len);
                    original_clipboard_text = std.heap.page_allocator.alloc(u8, u_str_len + 1) catch null;
                    if (original_clipboard_text) |buffer| {
                        std.mem.copyForwards(u8, buffer, @as([*]u8, @ptrCast(data_ptr))[0..u_str_len]);
                        buffer[u_str_len] = 0; // Null terminate
                    }
                }
                _ = api.GlobalUnlock(original_handle.?);
            }
        }
        _ = api.CloseClipboard();
    }

    // Prepare to set clipboard with our text
    if (api.OpenClipboard(null) != 0) {
        _ = api.EmptyClipboard();

        // Allocate global memory for the text
        const handle = api.GlobalAlloc(api.GMEM_MOVEABLE, text.len + 1);
        if (handle != null) {
            const data_ptr = api.GlobalLock(handle.?);
            if (data_ptr != null) {
                // Copy text to global memory
                @memcpy(@as([*]u8, @ptrCast(data_ptr))[0..text.len], text);
                @as([*]u8, @ptrCast(data_ptr))[text.len] = 0; // Null terminate
                _ = api.GlobalUnlock(handle.?);

                // Set clipboard data
                if (api.SetClipboardData(api.CF_TEXT, handle) == null) {
                    _ = api.GlobalFree(handle.?);
                    _ = api.CloseClipboard();
                    return false;
                }
            } else {
                _ = api.GlobalFree(handle.?);
                _ = api.CloseClipboard();
                return false;
            }
        } else {
            _ = api.CloseClipboard();
            return false;
        }

        _ = api.CloseClipboard();

        // Send paste command to the window
        _ = api.SendMessageA(target, api.WM_PASTE, 0, 0);

        // Wait a bit for paste to complete
        api.Sleep(50);

        // Restore original clipboard if we had saved it
        if (original_clipboard_text) |orig_text| {
            if (api.OpenClipboard(null) != 0) {
                _ = api.EmptyClipboard();

                const restore_handle = api.GlobalAlloc(api.GMEM_MOVEABLE, orig_text.len);
                if (restore_handle != null) {
                    const restore_ptr = api.GlobalLock(restore_handle.?);
                    if (restore_ptr != null) {
                        @memcpy(@as([*]u8, @ptrCast(restore_ptr))[0 .. orig_text.len - 1], orig_text[0 .. orig_text.len - 1]);
                        @as([*]u8, @ptrCast(restore_ptr))[orig_text.len - 1] = 0; // Null terminate
                        _ = api.GlobalUnlock(restore_handle.?);

                        _ = api.SetClipboardData(api.CF_TEXT, restore_handle);
                    } else {
                        _ = api.GlobalFree(restore_handle.?);
                    }
                }

                _ = api.CloseClipboard();
            }
        }

        return true;
    }

    return false;
}
