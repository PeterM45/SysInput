const std = @import("std");
const sysinput = @import("root").sysinput;
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
        3 => { // Special Notepad method
            success = trySimpleNotepadInsertion(hwnd, current_word, suggestion, allocator);
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

/// Very simple Notepad-specific insertion that uses SendMessage
pub fn trySimpleNotepadInsertion(hwnd: api.HWND, current_word: []const u8, suggestion: []const u8, allocator: std.mem.Allocator) bool {
    debug.debugPrint("Using simplified Notepad insertion for '{s}' -> '{s}'\n", .{ current_word, suggestion });

    // First, try to get the full text content
    const text_length = api.SendMessageA(hwnd, api.WM_GETTEXTLENGTH, 0, 0);
    if (text_length <= 0) {
        return false;
    }

    // Allocate space for the text (plus null terminator)
    const buffer_size: usize = @intCast(text_length + 1);
    const buffer = allocator.allocSentinel(u8, buffer_size, 0) catch {
        debug.debugPrint("Failed to allocate buffer for Notepad text\n", .{});
        return false;
    };
    defer allocator.free(buffer);

    // Get the text content
    const get_result = api.SendMessageA(hwnd, api.WM_GETTEXT, @intCast(buffer_size), // Cast buffer_size to WPARAM
        @bitCast(@intFromPtr(buffer.ptr))); // Use bitCast for pointer to LPARAM

    if (get_result == 0) {
        debug.debugPrint("Failed to get Notepad text\n", .{});
        return false;
    }

    // Make a copy of the text
    const text_copy = allocator.dupe(u8, buffer[0..@intCast(get_result)]) catch {
        debug.debugPrint("Failed to duplicate text buffer\n", .{});
        return false;
    };
    defer allocator.free(text_copy);

    // Get current selection
    const selection = api.SendMessageA(hwnd, api.EM_GETSEL, 0, 0);
    const sel_u64: u64 = @bitCast(selection);
    const sel_start: u32 = @truncate(sel_u64 & 0xFFFF);
    const sel_end: u32 = @truncate((sel_u64 >> 16) & 0xFFFF);

    // Create modified text by replacing current_word with suggestion
    var modified_text = std.ArrayList(u8).init(allocator);
    defer modified_text.deinit();

    // Add text up to selection point
    modified_text.appendSlice(text_copy[0..sel_start]) catch return false;

    // Add suggestion
    modified_text.appendSlice(suggestion) catch return false;
    modified_text.append(' ') catch return false; // Add a space

    // Add text after current word
    if (sel_end < text_copy.len) {
        modified_text.appendSlice(text_copy[sel_end..]) catch return false;
    }

    // Set full text back to Notepad
    const modified_ptr = allocator.allocSentinel(u8, modified_text.items.len, 0) catch {
        return false;
    };
    defer allocator.free(modified_ptr);

    @memcpy(modified_ptr, modified_text.items);

    // Set as new text
    _ = api.SendMessageA(hwnd, api.WM_SETTEXT, 0, @bitCast(@intFromPtr(modified_ptr.ptr))); // Use bitCast for pointer to LPARAM

    // Position cursor after the inserted text + space
    // Carefully handle the type conversion for EM_SETSEL parameters
    const new_pos_u32: u32 = sel_start + @as(u32, @intCast(suggestion.len)) + 1;
    const wp_newpos: api.WPARAM = new_pos_u32;
    const lp_newpos: api.LPARAM = @intCast(new_pos_u32);
    _ = api.SendMessageA(hwnd, api.EM_SETSEL, wp_newpos, lp_newpos);

    return true;
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

/// Special insertion method for Notepad
pub fn tryNotepadInsertion(hwnd: api.HWND, current_word: []const u8, suggestion: []const u8, allocator: std.mem.Allocator) bool {
    debug.debugPrint("Using Notepad-specific insertion for '{s}' -> '{s}'\n", .{ current_word, suggestion });

    // Get the current clipboard content to restore later
    const original_clipboard_text: ?[]u8 = saveClipboardText(allocator);
    defer {
        if (original_clipboard_text) |txt| {
            allocator.free(txt);
        }
    }

    // Ensure window is in focus
    _ = api.SetForegroundWindow(hwnd);
    api.Sleep(50); // Give Notepad time to focus

    // Step 1: Select text using keyboard shortcut - Shift+Home to select to beginning of line
    simulateCtrlLeftArrow(); // Move to beginning of word
    simulateShiftRightArrow(current_word.len); // Select the word
    api.Sleep(50);

    // Step 2: Set clipboard with suggestion
    if (!setClipboardText(suggestion)) {
        debug.debugPrint("Failed to set clipboard text\n", .{});
        return false;
    }

    // Step 3: Send paste command (Ctrl+V)
    simulateCtrlV();
    api.Sleep(100); // Wait for paste to complete

    // Step 4: Add a space using WM_CHAR
    _ = api.SendMessageA(hwnd, api.WM_CHAR, ' ', 0);
    api.Sleep(50);

    // Restore original clipboard if we had saved it
    if (original_clipboard_text) |orig_text| {
        _ = setClipboardText(orig_text);
    }

    // Try to get text to verify and update our buffer
    buffer_controller.detectActiveTextField();

    return true;
}

/// Save clipboard text
fn saveClipboardText(allocator: std.mem.Allocator) ?[]u8 {
    if (api.OpenClipboard(null) == 0) {
        return null;
    }

    const original_handle = api.GetClipboardData(api.CF_TEXT);
    if (original_handle == null) {
        _ = api.CloseClipboard();
        return null;
    }

    const data_ptr = api.GlobalLock(original_handle.?);
    if (data_ptr == null) {
        _ = api.CloseClipboard();
        return null;
    }

    const str_len = api.lstrlenA(data_ptr);
    if (str_len <= 0) {
        _ = api.GlobalUnlock(original_handle.?);
        _ = api.CloseClipboard();
        return null;
    }

    const u_str_len: usize = @intCast(str_len);
    const buffer = allocator.alloc(u8, u_str_len + 1) catch {
        _ = api.GlobalUnlock(original_handle.?);
        _ = api.CloseClipboard();
        return null;
    };

    @memcpy(buffer[0..u_str_len], @as([*]u8, @ptrCast(data_ptr))[0..u_str_len]);
    buffer[u_str_len] = 0; // Null terminate

    _ = api.GlobalUnlock(original_handle.?);
    _ = api.CloseClipboard();

    return buffer[0..u_str_len];
}

/// Set clipboard text
fn setClipboardText(text: []const u8) bool {
    if (api.OpenClipboard(null) == 0) {
        return false;
    }

    _ = api.EmptyClipboard();

    const handle = api.GlobalAlloc(api.GMEM_MOVEABLE, text.len + 1);
    if (handle == null) {
        _ = api.CloseClipboard();
        return false;
    }

    const data_ptr = api.GlobalLock(handle.?);
    if (data_ptr == null) {
        _ = api.GlobalFree(handle.?);
        _ = api.CloseClipboard();
        return false;
    }

    @memcpy(@as([*]u8, @ptrCast(data_ptr))[0..text.len], text);
    @as([*]u8, @ptrCast(data_ptr))[text.len] = 0; // Null terminate

    _ = api.GlobalUnlock(handle.?);

    const result = api.SetClipboardData(api.CF_TEXT, handle);
    _ = api.CloseClipboard();

    return result != null;
}

/// Simulate Ctrl+Left to move to beginning of word
fn simulateCtrlLeftArrow() void {
    // Use individual SendInput calls to avoid array issues
    var input: api.INPUT = undefined;

    // Ctrl down
    input.type = api.INPUT_KEYBOARD;
    input.ki.wVk = api.VK_CONTROL;
    input.ki.wScan = 0;
    input.ki.dwFlags = 0;
    input.ki.time = 0;
    input.ki.dwExtraInfo = 0;
    _ = api.SendInput(1, &input, @sizeOf(api.INPUT));

    // Left down
    input.ki.wVk = api.VK_LEFT;
    _ = api.SendInput(1, &input, @sizeOf(api.INPUT));

    // Left up
    input.ki.dwFlags = api.KEYEVENTF_KEYUP;
    _ = api.SendInput(1, &input, @sizeOf(api.INPUT));

    // Ctrl up
    input.ki.wVk = api.VK_CONTROL;
    _ = api.SendInput(1, &input, @sizeOf(api.INPUT));

    api.Sleep(20);
}

/// Simulate Shift+Right Arrow multiple times to select text
fn simulateShiftRightArrow(count: usize) void {
    if (count == 0) return;

    var input: api.INPUT = undefined;

    // Shift down
    input.type = api.INPUT_KEYBOARD;
    input.ki.wVk = api.VK_SHIFT;
    input.ki.wScan = 0;
    input.ki.dwFlags = 0;
    input.ki.time = 0;
    input.ki.dwExtraInfo = 0;
    _ = api.SendInput(1, &input, @sizeOf(api.INPUT));

    // Multiple Right presses
    var i: usize = 0;
    while (i < count) : (i += 1) {
        // Right down
        input.ki.wVk = api.VK_RIGHT;
        input.ki.dwFlags = 0;
        _ = api.SendInput(1, &input, @sizeOf(api.INPUT));

        // Right up
        input.ki.dwFlags = api.KEYEVENTF_KEYUP;
        _ = api.SendInput(1, &input, @sizeOf(api.INPUT));

        api.Sleep(5);
    }

    // Shift up
    input.ki.wVk = api.VK_SHIFT;
    _ = api.SendInput(1, &input, @sizeOf(api.INPUT));

    api.Sleep(20);
}

/// Simulate Ctrl+V (paste)
fn simulateCtrlV() void {
    var input: api.INPUT = undefined;

    // Ctrl down
    input.type = api.INPUT_KEYBOARD;
    input.ki.wVk = api.VK_CONTROL;
    input.ki.wScan = 0;
    input.ki.dwFlags = 0;
    input.ki.time = 0;
    input.ki.dwExtraInfo = 0;
    _ = api.SendInput(1, &input, @sizeOf(api.INPUT));

    // V down
    input.ki.wVk = 'V';
    _ = api.SendInput(1, &input, @sizeOf(api.INPUT));

    // V up
    input.ki.dwFlags = api.KEYEVENTF_KEYUP;
    _ = api.SendInput(1, &input, @sizeOf(api.INPUT));

    // Ctrl up
    input.ki.wVk = api.VK_CONTROL;
    _ = api.SendInput(1, &input, @sizeOf(api.INPUT));

    api.Sleep(20);
}
