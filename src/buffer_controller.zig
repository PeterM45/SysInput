const std = @import("std");
const sysinput = @import("sysinput.zig");

const buffer = sysinput.core.buffer;
const api = sysinput.win32.api;
const detection = sysinput.input.text_field;
const suggestion_handler = sysinput.suggestion_handler;
const debug = sysinput.core.debug;

/// Sync mode determines which synchronization strategy to use
pub const SyncMode = enum(u8) {
    Normal = 0, // Use normal text field update
    Clipboard = 1, // Use clipboard-based method
    Simulation = 2, // Use key simulation
};

var buffer_allocator: std.mem.Allocator = undefined;

/// Global buffer manager to track typed text
pub var buffer_manager: buffer.BufferManager = undefined;

/// Global text field manager for detecting active text fields
pub var text_field_manager: detection.TextFieldManager = undefined;

/// Last known text content - used for change detection and verification
var last_known_text: []u8 = &[_]u8{};

/// Sync attempt counter for retry mechanism
var sync_attempt_count: u8 = 0;

/// Map to remember which sync mode works best with each window class
var window_class_to_mode = std.StringHashMap(u8).init(std.heap.page_allocator);

pub fn init(allocator: std.mem.Allocator) !void {
    buffer_allocator = allocator;
    buffer_manager = buffer.BufferManager.init(allocator);
    text_field_manager = detection.TextFieldManager.init(allocator);
    last_known_text = try allocator.alloc(u8, 0);

    // Initialize window class map with proper allocator
    window_class_to_mode = std.StringHashMap(u8).init(allocator);
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

    if (syncTextFieldWithBufferAndVerify()) {
        debug.debugPrint("Text field sync succeeded\n", .{});
    } else {
        debug.debugPrint("All sync methods failed\n", .{});
    }
}

/// Try updating text field using standard messages
fn tryNormalTextFieldUpdate(content: []const u8) bool {
    const focus_hwnd = api.GetFocus();
    if (focus_hwnd == null) {
        return false;
    }

    // Select all text
    _ = api.SendMessageA(focus_hwnd.?, api.EM_SETSEL, 0, -1);

    // Replace with our content
    const text_buffer = std.heap.page_allocator.allocSentinel(u8, content.len, 0) catch {
        return false;
    };
    defer std.heap.page_allocator.free(text_buffer);

    @memcpy(text_buffer, content);

    const result = api.SendMessageA(focus_hwnd.?, api.EM_REPLACESEL, 1, // Allow undo
        @as(api.LPARAM, @intCast(@intFromPtr(text_buffer.ptr))));

    return result != 0;
}

/// Try updating using clipboard
fn tryClipboardUpdate(content: []const u8) bool {
    const focus_hwnd = api.GetFocus();
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
    if (api.OpenClipboard(null) != 0) {
        const original_handle = api.GetClipboardData(api.CF_TEXT);
        if (original_handle != null) {
            const data_ptr = api.GlobalLock(original_handle.?);
            if (data_ptr != null) {
                const str_len = api.lstrlenA(data_ptr);
                if (str_len > 0) {
                    const u_str_len: usize = @intCast(str_len);
                    original_clipboard_text = std.heap.page_allocator.alloc(u8, u_str_len + 1) catch null;
                    if (original_clipboard_text) |text_buffer| {
                        std.mem.copyForwards(u8, text_buffer, @as([*]u8, @ptrCast(data_ptr))[0..u_str_len]);
                        text_buffer[u_str_len] = 0; // Null terminate
                    }
                }
                _ = api.GlobalUnlock(original_handle.?);
            }
        }
        _ = api.CloseClipboard();
    }

    // Set clipboard with new content
    if (api.OpenClipboard(null) != 0) {
        _ = api.EmptyClipboard();

        const handle = api.GlobalAlloc(api.GMEM_MOVEABLE, content.len + 1);
        if (handle != null) {
            const data_ptr = api.GlobalLock(handle.?);
            if (data_ptr != null) {
                @memcpy(@as([*]u8, @ptrCast(data_ptr))[0..content.len], content);
                @as([*]u8, @ptrCast(data_ptr))[content.len] = 0; // Null terminate
                _ = api.GlobalUnlock(handle.?);

                _ = api.SetClipboardData(api.CF_TEXT, handle);
            }
        }

        _ = api.CloseClipboard();

        // Select all text in control
        _ = api.SendMessageA(focus_hwnd.?, api.EM_SETSEL, 0, -1);

        // Send paste command
        _ = api.SendMessageA(focus_hwnd.?, api.WM_PASTE, 0, 0);

        // Wait for paste to complete
        api.Sleep(50);

        // Restore original clipboard if needed
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

/// Try updating using key simulation
fn tryKeySimulation(content: []const u8) bool {
    const focus_hwnd = api.GetFocus();
    if (focus_hwnd == null) {
        return false;
    }

    // Bring window to foreground
    _ = api.SetForegroundWindow(focus_hwnd.?);

    // Select all existing text using Ctrl+A
    // Simulate Ctrl down
    var key_input: api.INPUT = undefined;
    key_input.type = api.INPUT_KEYBOARD;
    key_input.ki.wVk = api.VK_CONTROL;
    key_input.ki.wScan = 0;
    key_input.ki.dwFlags = 0; // Key down
    key_input.ki.time = 0;
    key_input.ki.dwExtraInfo = 0;
    _ = api.SendInput(1, &key_input, @sizeOf(api.INPUT));

    // Send A key
    key_input.ki.wVk = 'A';
    _ = api.SendInput(1, &key_input, @sizeOf(api.INPUT));

    // Release A key
    key_input.ki.wVk = 'A';
    key_input.ki.dwFlags = api.KEYEVENTF_KEYUP;
    _ = api.SendInput(1, &key_input, @sizeOf(api.INPUT));

    // Release Ctrl key
    key_input.ki.wVk = api.VK_CONTROL;
    _ = api.SendInput(1, &key_input, @sizeOf(api.INPUT));

    // Short delay
    api.Sleep(30);

    // Send each character
    for (content) |c| {
        key_input.ki.wVk = 0;
        key_input.ki.wScan = c;
        key_input.ki.dwFlags = api.KEYEVENTF_UNICODE;
        _ = api.SendInput(1, &key_input, @sizeOf(api.INPUT));

        key_input.ki.dwFlags = api.KEYEVENTF_UNICODE | api.KEYEVENTF_KEYUP;
        _ = api.SendInput(1, &key_input, @sizeOf(api.INPUT));

        api.Sleep(1); // Very short delay between keys
    }

    return true;
}

/// Print the current buffer state and process text for autocompletion
pub fn printBufferState() void {
    const content = buffer_manager.getCurrentText();
    // Print content with safe escaping for non-printable characters
    debug.debugPrint("Buffer: \"{s}\"\n", .{content});
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

/// Synchronize buffer content with active text field, with verification
pub fn syncTextFieldWithBufferAndVerify() bool {
    if (!text_field_manager.has_active_field) {
        return false;
    }

    // Store the content we want to insert
    const content = buffer_manager.getCurrentText();
    std.debug.print("Syncing buffer to text field: \"{s}\"\n", .{content});

    // Get window class to determine best method
    const focus_hwnd = api.GetFocus();
    var preferred_mode: ?SyncMode = null;

    if (focus_hwnd != null) {
        var class_name: [64]u8 = [_]u8{0} ** 64;
        const class_ptr: [*:0]u8 = @ptrCast(&class_name);
        const class_len = detection.GetClassNameA(focus_hwnd.?, class_ptr, 64);

        if (class_len > 0) {
            const class_slice = class_name[0..@intCast(class_len)];
            debug.debugPrint("Window class: {s}\n", .{class_slice});

            // Check if we have a preferred method for this class
            if (window_class_to_mode.get(class_slice)) |mode_val| {
                preferred_mode = @as(SyncMode, @enumFromInt(mode_val));
                debug.debugPrint("Using preferred sync mode: {s}\n", .{@tagName(preferred_mode.?)});
            }
        }
    }

    // Try methods in order of preference
    var success = false;

    // Try preferred method first if we have one
    if (preferred_mode) |mode| {
        success = trySyncMethod(mode, content);
        if (success) {
            debug.debugPrint("Preferred method {s} succeeded\n", .{@tagName(mode)});
            return true;
        }
    }

    // Otherwise, try methods in default order (skipping any we already tried)
    const methods = [_]SyncMode{ .Normal, .Clipboard, .Simulation };

    for (methods) |mode| {
        // Skip if this was already tried as the preferred method
        if (preferred_mode != null and mode == preferred_mode.?) {
            continue;
        }

        success = trySyncMethod(mode, content);
        if (success) {
            // Remember this successful method for this window class
            if (focus_hwnd != null) {
                var class_name: [64]u8 = [_]u8{0} ** 64;
                const class_ptr: [*:0]u8 = @ptrCast(&class_name);
                const class_len = detection.GetClassNameA(focus_hwnd.?, class_ptr, 64);

                if (class_len > 0) {
                    const class_slice = class_name[0..@intCast(class_len)];
                    const owned_class = buffer_allocator.dupe(u8, class_slice) catch {
                        debug.debugPrint("Failed to allocate for class name\n", .{});
                        return true;
                    };

                    window_class_to_mode.put(owned_class, @intFromEnum(mode)) catch {
                        buffer_allocator.free(owned_class);
                        debug.debugPrint("Failed to store class preference\n", .{});
                    };

                    debug.debugPrint("Learned: {s} works best with {s}\n", .{ class_slice, @tagName(mode) });
                }
            }

            return true;
        }
    }

    std.debug.print("Failed to update text field reliably\n", .{});
    return false;
}

/// Try a specific sync method with verification
fn trySyncMethod(mode: SyncMode, content: []const u8) bool {
    var success = false;

    switch (mode) {
        .Normal => {
            success = tryNormalTextFieldUpdate(content);
        },
        .Clipboard => {
            success = tryClipboardUpdate(content);
        },
        .Simulation => {
            success = tryKeySimulation(content);
            // Give more time for key simulation to complete
            if (success) api.Sleep(100);
        },
    }

    // Verify success
    if (success) {
        success = verifyTextUpdate(content);
        if (success) {
            debug.debugPrint("{s} succeeded and verified\n", .{@tagName(mode)});
        } else {
            debug.debugPrint("{s} appeared to succeed but failed verification\n", .{@tagName(mode)});
        }
    }

    return success;
}

/// Verify text update succeeded by reading back from the control
fn verifyTextUpdate(expected_content: []const u8) bool {
    const updated_text = text_field_manager.getActiveFieldText() catch |err| {
        std.debug.print("Failed to get updated text: {}\n", .{err});
        return false;
    };
    defer buffer_allocator.free(updated_text);

    // Special case: If we're expecting empty text, any very short text is ok
    if (expected_content.len == 0 and updated_text.len < 3) {
        return true;
    }

    // Compare updated text with what we expected - allow partial matches
    // since some applications format input or add content
    if (updated_text.len >= expected_content.len) {
        // Check if updated_text contains our content
        if (std.mem.indexOf(u8, updated_text, expected_content) != null) {
            return true;
        }
    } else if (expected_content.len > 0 and updated_text.len > 0) {
        // Or if our content contains the updated text
        if (std.mem.indexOf(u8, expected_content, updated_text) != null) {
            return true;
        }
    }

    return false;
}

/// Cleanup resources
pub fn deinit() void {
    if (last_known_text.len > 0) {
        buffer_allocator.free(last_known_text);
    }

    // Clean up window_class_to_mode map
    var it = window_class_to_mode.iterator();
    while (it.next()) |entry| {
        buffer_allocator.free(entry.key_ptr.*);
    }
    window_class_to_mode.deinit();
}
