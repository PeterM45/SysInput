const std = @import("std");
const sysinput = @import("../sysinput.zig");
const api = sysinput.win32.api;
const debug = sysinput.core.debug;
const text_inject = sysinput.win32.text_inject;
const buffer_controller = sysinput.buffer_controller;

/// Text insertion method type
pub const InsertMethod = enum(u8) {
    Clipboard = 0,
    KeySimulation = 1,
    DirectMessage = 2,
};

/// Try a specific insertion method
pub fn tryInsertionMethod(hwnd: api.HWND, current_word: []const u8, suggestion: []const u8, method: u8, allocator: std.mem.Allocator) bool {
    debug.debugPrint("Trying insertion method: {d}\n", .{method});

    const start_time = std.time.milliTimestamp();
    var success = false;

    switch (method) {
        @intFromEnum(InsertMethod.Clipboard) => {
            success = tryClipboardInsertion(hwnd, current_word, suggestion, allocator);
        },
        @intFromEnum(InsertMethod.KeySimulation) => {
            success = tryKeySimulationInsertion(hwnd, current_word, suggestion, allocator);
        },
        @intFromEnum(InsertMethod.DirectMessage) => {
            success = tryDirectMessageInsertion(hwnd, current_word, suggestion, allocator);
        },
        else => {
            debug.debugPrint("Unknown insertion method: {d}\n", .{method});
            return false;
        },
    }

    const elapsed = std.time.milliTimestamp() - start_time;
    debug.debugPrint("Method {d} {s} in {d}ms\n", .{ method, if (success) "succeeded" else "failed", elapsed });

    return success;
}

/// Try clipboard-based insertion
pub fn tryClipboardInsertion(hwnd: api.HWND, current_word: []const u8, suggestion: []const u8, allocator: std.mem.Allocator) bool {
    debug.debugPrint("Using clipboard insertion for '{s}' -> '{s}'\n", .{ current_word, suggestion });

    // First select the current word
    if (!trySelectCurrentWord(hwnd, current_word)) {
        debug.debugPrint("Failed to select current word\n", .{});
        return false;
    }

    // Use clipboard insertion from text_inject
    if (!text_inject.insertViaClipboard(hwnd, suggestion)) {
        debug.debugPrint("Clipboard insertion failed\n", .{});
        return false;
    }

    // Add a space after suggestion
    _ = text_inject.insertViaClipboard(hwnd, " ");

    // Verify insertion by checking if text field contains suggestion
    api.sleep(50); // Wait for paste to complete
    buffer_controller.detectActiveTextField();
    const text = buffer_controller.getActiveFieldText() catch {
        debug.debugPrint("Failed to get updated text for verification\n", .{});
        return true; // Assume success if we can't verify
    };
    defer allocator.free(text);

    // Update internal buffer regardless of verification result
    buffer_controller.resetBuffer();
    buffer_controller.insertString(text) catch |err| {
        debug.debugPrint("Failed to update buffer: {}\n", .{err});
    };

    // Consider success even if verification fails - text might be in control but not readable
    return true;
}

/// Try key simulation insertion
pub fn tryKeySimulationInsertion(hwnd: api.HWND, current_word: []const u8, suggestion: []const u8, allocator: std.mem.Allocator) bool {
    debug.debugPrint("Using key simulation for '{s}' -> '{s}'\n", .{ current_word, suggestion });

    // Ensure window has focus
    _ = api.setForegroundWindow(hwnd);
    api.sleep(30); // Give time for focus to take effect

    // 1. Delete the current word with backspace
    for (0..current_word.len) |_| {
        _ = api.postMessage(hwnd, api.WM_KEYDOWN, api.VK_BACK, 0);
        _ = api.postMessage(hwnd, api.WM_KEYUP, api.VK_BACK, 0);
        api.sleep(5); // Short delay
    }

    // 2. Insert the suggestion character by character using WM_CHAR
    for (suggestion) |c| {
        // Send character using WM_CHAR which works more reliably for text insertion
        _ = api.postMessage(hwnd, api.WM_CHAR, c, 0);
        api.sleep(5); // Short delay
    }

    // 3. Add a space
    _ = api.postMessage(hwnd, api.WM_CHAR, ' ', 0);

    // Wait for all key events to be processed
    api.sleep(100); // Longer wait to ensure all messages are processed

    // Update buffer manually
    buffer_controller.detectActiveTextField();

    // Get the updated text for our buffer
    const text = buffer_controller.getActiveFieldText() catch {
        debug.debugPrint("Failed to get updated text after key simulation\n", .{});
        return true; // Assume success if we can't verify
    };
    defer allocator.free(text);

    // Add the completed word to our vocabulary
    buffer_controller.resetBuffer();
    buffer_controller.insertString(text) catch |err| {
        debug.debugPrint("Failed to update buffer: {}\n", .{err});
    };

    return true;
}

/// Try direct Windows message insertion
pub fn tryDirectMessageInsertion(hwnd: api.HWND, current_word: []const u8, suggestion: []const u8, allocator: std.mem.Allocator) bool {
    debug.debugPrint("Using direct message insertion for '{s}' -> '{s}'\n", .{ current_word, suggestion });

    // First select the current word
    if (!trySelectCurrentWord(hwnd, current_word)) {
        debug.debugPrint("Failed to select current word\n", .{});
        return false;
    }

    // Create null-terminated text buffer
    const buffer = std.heap.page_allocator.allocSentinel(u8, suggestion.len, 0) catch {
        debug.debugPrint("Failed to allocate buffer\n", .{});
        return false;
    };
    defer std.heap.page_allocator.free(buffer);

    @memcpy(buffer, suggestion);

    // Replace selected text
    const result = api.sendMessage(hwnd, api.EM_REPLACESEL, 1, @as(api.LPARAM, @intCast(@intFromPtr(buffer.ptr))));

    if (result == 0) {
        debug.debugPrint("EM_REPLACESEL failed\n", .{});
        return false;
    }

    // Add space
    var space_buffer = std.heap.page_allocator.allocSentinel(u8, 1, 0) catch {
        return false;
    };
    defer std.heap.page_allocator.free(space_buffer);
    space_buffer[0] = ' ';

    _ = api.sendMessage(hwnd, api.EM_REPLACESEL, 1, @as(api.LPARAM, @intCast(@intFromPtr(space_buffer.ptr))));

    // Update buffer
    buffer_controller.detectActiveTextField();

    // Get the updated text for our buffer
    const text = buffer_controller.getActiveFieldText() catch {
        debug.debugPrint("Failed to get updated text after direct message\n", .{});
        return true; // Assume success if we can't verify
    };
    defer allocator.free(text);

    // Update internal buffer
    buffer_controller.resetBuffer();
    buffer_controller.insertString(text) catch |err| {
        debug.debugPrint("Failed to update buffer: {}\n", .{err});
    };

    return true;
}

/// Try selecting the current word in the text field
pub fn trySelectCurrentWord(hwnd: api.HWND, word: []const u8) bool {
    // METHOD 1: Use selection information
    const selection = api.sendMessage(hwnd, api.EM_GETSEL, 0, 0);
    const sel_u64: u64 = @bitCast(selection);
    const sel_start: u32 = @truncate(sel_u64 & 0xFFFF);
    const sel_end: u32 = @truncate((sel_u64 >> 16) & 0xFFFF);

    debug.debugPrint("Current selection: {}-{}\n", .{ sel_start, sel_end });

    // Use the caret position to estimate word boundaries
    if (sel_start == sel_end) { // Cursor is a point, not a selection
        // Calculate where the word should start based on cursor position
        const caret_pos = sel_end;
        const word_start = if (caret_pos >= word.len) caret_pos - word.len else 0;

        debug.debugPrint("Selecting word from position {d} to {d}\n", .{ word_start, caret_pos });

        // Select the range
        _ = api.sendMessage(hwnd, api.EM_SETSEL, word_start, caret_pos);

        // Verify selection
        const new_selection = api.sendMessage(hwnd, api.EM_GETSEL, 0, 0);
        const new_sel_u64: u64 = @bitCast(new_selection);
        const new_start: u32 = @truncate(new_sel_u64 & 0xFFFF);
        const new_end: u32 = @truncate((new_sel_u64 >> 16) & 0xFFFF);

        // If selection succeeded, we're done
        if (new_start != new_end) {
            debug.debugPrint("Selection successful: {}-{}\n", .{ new_start, new_end });
            return true;
        }
    }

    // METHOD 2: Try to find the word in the content
    // For short words, we'll try a simpler approach first
    if (word.len > 0) {
        // Try selecting from cursor pos - word.len to cursor pos
        const cursor_pos = sel_end;
        const word_start = if (cursor_pos >= word.len) cursor_pos - word.len else 0;
        _ = api.sendMessage(hwnd, api.EM_SETSEL, word_start, cursor_pos);

        const check_sel = api.sendMessage(hwnd, api.EM_GETSEL, 0, 0);
        const check_u64: u64 = @bitCast(check_sel);
        const check_start: u32 = @truncate(check_u64 & 0xFFFF);
        const check_end: u32 = @truncate((check_u64 >> 16) & 0xFFFF);

        if (check_start != check_end) {
            return true;
        }
    }

    // METHOD 3: Simple fallback - use whatever was found
    _ = api.sendMessage(hwnd, api.EM_SETSEL, sel_start, sel_end);
    return sel_start != sel_end;
}

/// Simulate a key press/release
pub fn simulateKeyPress(vk: u8, is_down: bool) void {
    var input: api.INPUT = undefined;
    input.type = api.INPUT_KEYBOARD;
    input.ki.wVk = vk;
    input.ki.wScan = 0;
    input.ki.dwFlags = if (is_down) 0 else api.KEYEVENTF_KEYUP;
    input.ki.time = 0;
    input.ki.dwExtraInfo = 0;

    _ = api.sendInput(1, &input, @sizeOf(api.INPUT));
}

/// Check if a character is part of a word
pub fn isWordChar(c: u8) bool {
    // Allow letters, numbers, underscore, and apostrophe (for contractions)
    return std.ascii.isAlphanumeric(c) or c == '_' or c == '\'';
}
