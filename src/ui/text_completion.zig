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

/// Insert text as a selected block
/// Returns true if successful
pub fn insertTextAsSelection(hwnd: common.HWND, text: []const u8) bool {
    std.debug.print("Inserting text as selection: '{s}'\n", .{text});

    // Skip if no text to insert
    if (text.len == 0) {
        std.debug.print("No text to insert\n", .{});
        return false;
    }

    // Create null-terminated text using page allocator
    const buffer = std.heap.page_allocator.allocSentinel(u8, text.len, 0) catch {
        std.debug.print("Failed to allocate buffer for text insertion\n", .{});
        return false;
    };
    defer std.heap.page_allocator.free(buffer);

    // Copy the text to the buffer
    @memcpy(buffer, text);

    // Debug information
    const before_sel = common.SendMessageA(hwnd, common.EM_GETSEL, 0, 0);
    const before_u64: u64 = @bitCast(before_sel);
    const before_start: u32 = @truncate(before_u64 & 0xFFFF);
    const before_end: u32 = @truncate((before_u64 >> 16) & 0xFFFF);
    std.debug.print("Selection before insert: {d}-{d}\n", .{ before_start, before_end });

    // First make sure selection is clear (start == end)
    _ = common.SendMessageA(hwnd, common.EM_SETSEL, before_end, before_end);

    // Insert the text
    const insert_result = common.SendMessageA(hwnd, common.EM_REPLACESEL, 1, // True to allow undo
        @as(common.LPARAM, @intCast(@intFromPtr(buffer.ptr))));

    // Check if successful
    if (insert_result == 0) {
        std.debug.print("EM_REPLACESEL failed\n", .{});
        return false;
    }

    // Get new selection position
    const after_sel = common.SendMessageA(hwnd, common.EM_GETSEL, 0, 0);
    const after_u64: u64 = @bitCast(after_sel);
    const after_start: u32 = @truncate(after_u64 & 0xFFFF);
    const after_end: u32 = @truncate((after_u64 >> 16) & 0xFFFF);
    std.debug.print("Selection after insert: {d}-{d}\n", .{ after_start, after_end });

    // Send a WM_CHAR message to simulate typing
    for (text) |c| {
        _ = common.PostMessageA(hwnd, common.WM_CHAR, @as(common.WPARAM, c), 0);
        std.debug.print("Posted character: {c}\n", .{c});
    }

    return true;
}
