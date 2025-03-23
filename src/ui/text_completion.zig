const std = @import("std");
const common = @import("../win32/common.zig");
const ui_utils = @import("ui_utils.zig");

/// Try to apply completion using direct text replacement methods
/// Returns true if successful
pub fn tryDirectCompletion(partial_word: []const u8, suggestion: []const u8) bool {
    // Only proceed if the suggestion starts with the partial word
    if (partial_word.len == 0 or !std.mem.startsWith(u8, suggestion, partial_word)) {
        return false;
    }

    // Get the active window and control
    const hwnd = common.GetForegroundWindow();
    if (hwnd == null) return false;

    // Get the control with focus (usually the text field)
    const focus_hwnd = common.GetFocus();
    if (focus_hwnd == null) return false;

    std.debug.print("Trying direct completion: '{s}' -> '{s}'\n", .{ partial_word, suggestion });

    // Try to get selection/position in text field using standard approach
    const selection_result = common.SendMessageA(focus_hwnd.?, common.EM_GETSEL, 0, 0);

    // Extract start and end positions from the result
    const result_u64: u64 = @bitCast(selection_result);
    const start: common.DWORD = @truncate(result_u64 & 0xFFFF);
    const end: common.DWORD = @truncate((result_u64 >> 16) & 0xFFFF);

    std.debug.print("Selection: {d}-{d}\n", .{ start, end });

    // If we have a valid selection position
    if (start != 0 or end != 0) {
        // Calculate what part of the word we need to add
        const completion = suggestion[partial_word.len..];

        // First, position the cursor at the end of the partial word
        _ = common.SendMessageA(focus_hwnd.?, common.EM_SETSEL, end, end);

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
    const hwnd = common.GetForegroundWindow();
    if (hwnd == null) return false;

    // Get the control with focus (usually the text field)
    const focus_hwnd = common.GetFocus();
    if (focus_hwnd == null) return false;

    std.debug.print("Trying selection completion: '{s}' -> '{s}'\n", .{ partial_word, suggestion });

    // Try to get text length in the control
    const text_length = common.SendMessageA(focus_hwnd.?, common.WM_GETTEXTLENGTH, 0, 0);
    if (text_length <= 0) return false;

    // Calculate what part of the word we need to add
    const completion = suggestion[partial_word.len..];

    // For selection-based completion, we attempt to:
    // 1. Set the cursor at the current position
    // 2. Insert the completion text
    // This method may work for controls that don't support EM_GETSEL/EM_SETSEL properly

    // Get the current caret position (usually at the end of the partial word)
    const current_pos = common.SendMessageA(focus_hwnd.?, common.EM_GETSEL, 0, 0);
    // Extract high word (end position)
    const high_word: u32 = @intCast(@as(u64, @bitCast(current_pos)) >> 16);
    const caret_pos: common.DWORD = high_word & 0xFFFF;

    // Position the cursor and insert the completion
    _ = common.SendMessageA(focus_hwnd.?, common.EM_SETSEL, caret_pos, caret_pos);

    // Try to insert the completion
    return insertTextAsSelection(focus_hwnd.?, completion);
}

/// Insert text as a selected block using multiple approaches
/// Returns true if successful
pub fn insertTextAsSelection(hwnd: common.HWND, text: []const u8) bool {
    std.debug.print("Inserting text as selection: '{s}'\n", .{text});

    // Skip if no text to insert
    if (text.len == 0) {
        std.debug.print("No text to insert\n", .{});
        return false;
    }

    // Approach 1: Direct message-based insertion
    if (tryDirectInsertion(hwnd, text)) {
        std.debug.print("Direct insertion succeeded\n", .{});
        return true;
    }

    // Approach 2: Try clipboard-based approach
    if (tryClipboardInsertion(hwnd, text)) {
        std.debug.print("Clipboard insertion succeeded\n", .{});
        return true;
    }

    // Approach 3: Simulate typing of each character
    if (trySimulatedTyping(hwnd, text)) {
        std.debug.print("Simulated typing succeeded\n", .{});
        return true;
    }

    std.debug.print("All insertion methods failed\n", .{});
    return false;
}

/// Try direct Windows message-based insertion
fn tryDirectInsertion(hwnd: common.HWND, text: []const u8) bool {
    // Create null-terminated text
    const buffer = std.heap.page_allocator.allocSentinel(u8, text.len, 0) catch {
        std.debug.print("Failed to allocate buffer for text insertion\n", .{});
        return false;
    };
    defer std.heap.page_allocator.free(buffer);

    // Copy the text to the buffer
    @memcpy(buffer, text);

    // Debug: Check selection before insert
    const before_sel = common.SendMessageA(hwnd, common.EM_GETSEL, 0, 0);
    const before_u64: u64 = @bitCast(before_sel);
    const before_start: u32 = @truncate(before_u64 & 0xFFFF);
    const before_end: u32 = @truncate((before_u64 >> 16) & 0xFFFF);
    std.debug.print("Selection before insert: {d}-{d}\n", .{ before_start, before_end });

    // Insert the text using EM_REPLACESEL
    const insert_result = common.SendMessageA(hwnd, common.EM_REPLACESEL, 1, // True to allow undo
        @as(common.LPARAM, @intCast(@intFromPtr(buffer.ptr))));

    // Check if successful
    if (insert_result == 0) {
        std.debug.print("EM_REPLACESEL failed\n", .{});
        return false;
    }

    // Verify the insertion worked by checking selection
    const after_sel = common.SendMessageA(hwnd, common.EM_GETSEL, 0, 0);
    const after_u64: u64 = @bitCast(after_sel);
    const after_start: u32 = @truncate(after_u64 & 0xFFFF);
    const after_end: u32 = @truncate((after_u64 >> 16) & 0xFFFF);

    std.debug.print("Selection after insert: {d}-{d}\n", .{ after_start, after_end });

    // If selection didn't change, insertion likely failed
    if (before_end == after_end) {
        std.debug.print("Selection didn't change, insertion may have failed\n", .{});
        return false;
    }

    return true;
}

/// Try clipboard-based insertion
fn tryClipboardInsertion(hwnd: common.HWND, text: []const u8) bool {
    // Save original clipboard contents
    var original_clipboard_text: ?[]u8 = null;
    defer {
        if (original_clipboard_text) |txt| {
            std.heap.page_allocator.free(txt);
        }
    }

    // Try to save original clipboard contents
    if (common.OpenClipboard(null) != 0) {
        const original_handle = common.GetClipboardData(common.CF_TEXT);
        if (original_handle != null) {
            const data_ptr = common.GlobalLock(original_handle.?);
            if (data_ptr != null) {
                const str_len = common.lstrlenA(data_ptr);
                if (str_len > 0) {
                    const u_str_len: usize = @intCast(str_len);
                    original_clipboard_text = std.heap.page_allocator.alloc(u8, u_str_len + 1) catch null;
                    if (original_clipboard_text) |buffer| {
                        std.mem.copyForwards(u8, buffer, @as([*]u8, @ptrCast(data_ptr))[0..u_str_len]);
                        buffer[u_str_len] = 0; // Null terminate
                    }
                }
                _ = common.GlobalUnlock(original_handle.?);
            }
        }
        _ = common.CloseClipboard();
    }

    // Prepare to set clipboard with our text
    if (common.OpenClipboard(null) != 0) {
        _ = common.EmptyClipboard();

        // Allocate global memory for the text
        const handle = common.GlobalAlloc(common.GMEM_MOVEABLE, text.len + 1);
        if (handle != null) {
            const data_ptr = common.GlobalLock(handle.?);
            if (data_ptr != null) {
                // Copy text to global memory
                @memcpy(@as([*]u8, @ptrCast(data_ptr))[0..text.len], text);
                @as([*]u8, @ptrCast(data_ptr))[text.len] = 0; // Null terminate
                _ = common.GlobalUnlock(handle.?);

                // Set clipboard data
                _ = common.SetClipboardData(common.CF_TEXT, handle);
            }
        }

        _ = common.CloseClipboard();

        // Send paste command to the window (Ctrl+V)
        _ = common.SendMessageA(hwnd, common.WM_PASTE, 0, 0);

        // Wait a bit for paste to complete
        common.Sleep(50);

        // Restore original clipboard if we had saved it
        if (original_clipboard_text) |orig_text| {
            if (common.OpenClipboard(null) != 0) {
                _ = common.EmptyClipboard();

                const restore_handle = common.GlobalAlloc(common.GMEM_MOVEABLE, orig_text.len);
                if (restore_handle != null) {
                    const restore_ptr = common.GlobalLock(restore_handle.?);
                    if (restore_ptr != null) {
                        @memcpy(@as([*]u8, @ptrCast(restore_ptr))[0 .. orig_text.len - 1], orig_text[0 .. orig_text.len - 1]);
                        @as([*]u8, @ptrCast(restore_ptr))[orig_text.len - 1] = 0; // Null terminate
                        _ = common.GlobalUnlock(restore_handle.?);

                        _ = common.SetClipboardData(common.CF_TEXT, restore_handle);
                    }
                }

                _ = common.CloseClipboard();
            }
        }

        return true;
    }

    return false;
}

/// Try simulated typing
fn trySimulatedTyping(hwnd: common.HWND, text: []const u8) bool {
    // Bring window to front to ensure it receives input
    _ = common.SetForegroundWindow(hwnd);

    // Give the window time to process
    common.Sleep(50);

    // Send each character as a key press
    for (text) |c| {
        // Send character using WM_CHAR
        _ = common.SendMessageA(hwnd, common.WM_CHAR, @as(common.WPARAM, c), 0);

        // Small delay between keystrokes for reliability
        common.Sleep(5);
    }

    return true;
}
