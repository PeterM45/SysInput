const std = @import("std");
const buffer = @import("buffer/buffer.zig");
const common = @import("win32/common.zig");
const detection = @import("detection/text_field.zig");
const suggestion_handler = @import("suggestion_handler.zig");

var buffer_allocator: std.mem.Allocator = undefined;

/// Global buffer manager to track typed text
pub var buffer_manager: buffer.BufferManager = undefined;

/// Global text field manager for detecting active text fields
pub var text_field_manager: detection.TextFieldManager = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    buffer_allocator = allocator;
    buffer_manager = buffer.BufferManager.init(allocator);
    text_field_manager = detection.TextFieldManager.init(allocator);
}

/// Detect the active text field and sync with our buffer
pub fn detectActiveTextField() void {
    const active_field_found = text_field_manager.detectActiveField();

    if (active_field_found) {
        std.debug.print("Active text field detected\n", .{});

        // Get the text content from the field
        const text = text_field_manager.getActiveFieldText() catch |err| {
            std.debug.print("Failed to get text field content: {}\n", .{err});
            return;
        };
        defer buffer_allocator.free(text);

        // Update our buffer with the current text field content
        buffer_manager.resetBuffer();
        buffer_manager.insertString(text) catch |err| {
            std.debug.print("Failed to sync buffer with text field: {}\n", .{err});
        };

        std.debug.print("Synced buffer with text field content: \"{s}\"\n", .{text});
    } else {
        std.debug.print("No active text field found\n", .{});
    }
}

/// Sync the text field with our buffer content using multiple methods
pub fn syncTextFieldWithBuffer() void {
    if (!text_field_manager.has_active_field) {
        return;
    }

    const content = buffer_manager.getCurrentText();
    std.debug.print("Syncing buffer to text field: \"{s}\"\n", .{content});

    // Try using normal text field update
    if (tryNormalTextFieldUpdate(content)) {
        std.debug.print("Normal text field update succeeded\n", .{});
        return;
    }

    // Try using clipboard method as fallback
    if (tryClipboardUpdate(content)) {
        std.debug.print("Clipboard update succeeded\n", .{});
        return;
    }

    // Try using key simulation as last resort
    if (tryKeySimulation(content)) {
        std.debug.print("Key simulation succeeded\n", .{});
        return;
    }

    std.debug.print("Failed to update text field\n", .{});
}

/// Try updating text field using standard messages
fn tryNormalTextFieldUpdate(content: []const u8) bool {
    const focus_hwnd = common.GetFocus();
    if (focus_hwnd == null) {
        return false;
    }

    // Select all text
    _ = common.SendMessageA(focus_hwnd.?, common.EM_SETSEL, 0, -1);

    // Replace with our content
    const text_buffer = std.heap.page_allocator.allocSentinel(u8, content.len, 0) catch {
        return false;
    };
    defer std.heap.page_allocator.free(text_buffer);

    @memcpy(text_buffer, content);

    const result = common.SendMessageA(focus_hwnd.?, common.EM_REPLACESEL, 1, // Allow undo
        @as(common.LPARAM, @intCast(@intFromPtr(text_buffer.ptr))));

    return result != 0;
}

/// Try updating using clipboard
fn tryClipboardUpdate(content: []const u8) bool {
    const focus_hwnd = common.GetFocus();
    if (focus_hwnd == null) {
        return false;
    }

    // Save original clipboard contents
    var original_clipboard_text: ?[]u8 = null;
    defer {
        if (original_clipboard_text) |txt| {
            std.heap.page_allocator.free(txt);
        }
    }

    // Try to save original clipboard
    if (common.OpenClipboard(null) != 0) {
        const original_handle = common.GetClipboardData(common.CF_TEXT);
        if (original_handle != null) {
            const data_ptr = common.GlobalLock(original_handle.?);
            if (data_ptr != null) {
                const str_len = common.lstrlenA(data_ptr);
                if (str_len > 0) {
                    const u_str_len: usize = @intCast(str_len);
                    original_clipboard_text = std.heap.page_allocator.alloc(u8, u_str_len + 1) catch null;
                    if (original_clipboard_text) |text_buffer| {
                        std.mem.copyForwards(u8, text_buffer, @as([*]u8, @ptrCast(data_ptr))[0..u_str_len]);
                        text_buffer[u_str_len] = 0; // Null terminate
                    }
                }
                _ = common.GlobalUnlock(original_handle.?);
            }
        }
        _ = common.CloseClipboard();
    }

    // Set clipboard with new content
    if (common.OpenClipboard(null) != 0) {
        _ = common.EmptyClipboard();

        const handle = common.GlobalAlloc(common.GMEM_MOVEABLE, content.len + 1);
        if (handle != null) {
            const data_ptr = common.GlobalLock(handle.?);
            if (data_ptr != null) {
                @memcpy(@as([*]u8, @ptrCast(data_ptr))[0..content.len], content);
                @as([*]u8, @ptrCast(data_ptr))[content.len] = 0; // Null terminate
                _ = common.GlobalUnlock(handle.?);

                _ = common.SetClipboardData(common.CF_TEXT, handle);
            }
        }

        _ = common.CloseClipboard();

        // Select all text in control
        _ = common.SendMessageA(focus_hwnd.?, common.EM_SETSEL, 0, -1);

        // Send paste command
        _ = common.SendMessageA(focus_hwnd.?, common.WM_PASTE, 0, 0);

        // Wait for paste to complete
        common.Sleep(50);

        // Restore original clipboard if needed
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

/// Try updating using key simulation
fn tryKeySimulation(content: []const u8) bool {
    const focus_hwnd = common.GetFocus();
    if (focus_hwnd == null) {
        return false;
    }

    // Bring window to foreground
    _ = common.SetForegroundWindow(focus_hwnd.?);

    // Select all existing text using Ctrl+A
    // Simulate Ctrl down
    var key_input: common.INPUT = undefined;
    key_input.type = common.INPUT_KEYBOARD;
    key_input.ki.wVk = common.VK_CONTROL;
    key_input.ki.wScan = 0;
    key_input.ki.dwFlags = 0; // Key down
    key_input.ki.time = 0;
    key_input.ki.dwExtraInfo = 0;
    _ = common.SendInput(1, &key_input, @sizeOf(common.INPUT));

    // Send A key
    key_input.ki.wVk = 'A';
    _ = common.SendInput(1, &key_input, @sizeOf(common.INPUT));

    // Release A key
    key_input.ki.wVk = 'A';
    key_input.ki.dwFlags = common.KEYEVENTF_KEYUP;
    _ = common.SendInput(1, &key_input, @sizeOf(common.INPUT));

    // Release Ctrl key
    key_input.ki.wVk = common.VK_CONTROL;
    _ = common.SendInput(1, &key_input, @sizeOf(common.INPUT));

    // Short delay
    common.Sleep(30);

    // Send each character
    for (content) |c| {
        key_input.ki.wVk = 0;
        key_input.ki.wScan = c;
        key_input.ki.dwFlags = common.KEYEVENTF_UNICODE;
        _ = common.SendInput(1, &key_input, @sizeOf(common.INPUT));

        key_input.ki.dwFlags = common.KEYEVENTF_UNICODE | common.KEYEVENTF_KEYUP;
        _ = common.SendInput(1, &key_input, @sizeOf(common.INPUT));

        common.Sleep(1); // Very short delay between keys
    }

    return true;
}

/// Print the current buffer state and process text for autocompletion
pub fn printBufferState() void {
    const content = buffer_manager.getCurrentText();
    // Print content with safe escaping for non-printable characters
    std.debug.print("Buffer: \"", .{});
    for (content) |c| {
        if (std.ascii.isPrint(c)) {
            std.debug.print("{c}", .{c});
        } else {
            std.debug.print("\\x{X:0>2}", .{c});
        }
    }
    std.debug.print("\" (len: {})\n", .{content.len});

    const word = buffer_manager.getCurrentWord() catch {
        std.debug.print("Error getting current word\n", .{});
        return;
    };

    // Print word with safe escaping
    std.debug.print("Current word: \"", .{});
    for (word) |c| {
        if (std.ascii.isPrint(c)) {
            std.debug.print("{c}", .{c});
        } else {
            std.debug.print("\\x{X:0>2}", .{c});
        }
    }
    std.debug.print("\"\n", .{});

    // Process text through suggestion handler
    suggestion_handler.processTextForSuggestions(content) catch |err| {
        std.debug.print("Error processing text for autocompletion: {}\n", .{err});
    };

    // Set current word and get suggestions
    suggestion_handler.setCurrentWord(word);
    suggestion_handler.getAutocompleteSuggestions() catch |err| {
        std.debug.print("Error getting autocompletion suggestions: {}\n", .{err});
    };

    // Show suggestions if needed
    suggestion_handler.showSuggestions(content, word) catch |err| {
        std.debug.print("Error applying suggestions: {}\n", .{err});
    };

    // Check spelling
    if (word.len >= 2) {
        if (!suggestion_handler.isWordCorrect(word)) {
            // Safely print the word that has a spelling error
            std.debug.print("Spelling error detected: \"", .{});
            for (word) |c| {
                if (std.ascii.isPrint(c)) {
                    std.debug.print("{c}", .{c});
                } else {
                    std.debug.print("\\x{X:0>2}", .{c});
                }
            }
            std.debug.print("\"\n", .{});

            // Get spelling suggestions if word isn't too long
            if (word.len < 15) {
                suggestion_handler.getSpellingSuggestions(word) catch |err| {
                    std.debug.print("Error getting suggestions: {}\n", .{err});
                    return;
                };

                // Spelling suggestions will be printed by the suggestion handler
            }
        }
    }
}

/// Insert a string into the buffer
pub fn insertString(str: []const u8) !void {
    try buffer_manager.insertString(str);
    syncTextFieldWithBuffer();
}

/// Process backspace key
pub fn processBackspace() !void {
    try buffer_manager.processBackspace();
    syncTextFieldWithBuffer();
}

/// Process delete key
pub fn processDelete() !void {
    try buffer_manager.processDelete();
    syncTextFieldWithBuffer();
}

/// Process return/enter key
pub fn processReturn() !void {
    try buffer_manager.processKeyPress('\n', true);
    syncTextFieldWithBuffer();
}

/// Process a key press
pub fn processKeyPress(key: u8, is_char: bool) !void {
    try buffer_manager.processKeyPress(key, is_char);
    syncTextFieldWithBuffer();
}

/// A helper function to insert a test string
pub fn insertTestString() void {
    const test_string = "Hello, World!";
    insertString(test_string) catch |err| {
        std.debug.print("Error inserting test string: {}\n", .{err});
    };
}

/// Get current text from buffer
pub fn getCurrentText() []const u8 {
    return buffer_manager.getCurrentText();
}

/// Get current word from buffer
pub fn getCurrentWord() ![]const u8 {
    return buffer_manager.getCurrentWord();
}

/// Process backspace key, handling errors internally
pub fn handleBackspace() void {
    buffer_manager.processBackspace() catch |err| {
        std.debug.print("Backspace error: {}\n", .{err});
    };
    syncTextFieldWithBuffer();
}

/// Process delete key, handling errors internally
pub fn handleDelete() void {
    buffer_manager.processDelete() catch |err| {
        std.debug.print("Delete error: {}\n", .{err});
    };
    syncTextFieldWithBuffer();
}

/// Process character input, handling errors internally
pub fn handleCharInput(char: u8) void {
    buffer_manager.processKeyPress(char, true) catch |err| {
        std.debug.print("Key processing error: {}\n", .{err});
    };
    syncTextFieldWithBuffer();
}

/// Process return key, handling errors internally
pub fn handleReturn() void {
    buffer_manager.processKeyPress('\n', true) catch |err| {
        std.debug.print("Return key error: {}\n", .{err});
    };
    syncTextFieldWithBuffer();
}

/// Check if there's an active text field
pub fn hasActiveTextField() bool {
    return text_field_manager.has_active_field;
}

/// Get text from the active text field
pub fn getActiveFieldText() ![]u8 {
    return text_field_manager.getActiveFieldText();
}

/// Reset the active buffer
pub fn resetBuffer() void {
    buffer_manager.resetBuffer();
}

pub fn processCharInput(char: u8) !void {
    try buffer_manager.processKeyPress(char, true);
    syncTextFieldWithBuffer();
}
