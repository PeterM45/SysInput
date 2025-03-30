const std = @import("std");
const sysinput = @import("sysinput.zig");

const buffer = sysinput.core.buffer;
const api = sysinput.win32.api;
const detection = sysinput.input.text_field;
const manager = sysinput.suggestion.manager;
const debug = sysinput.core.debug;
const text_inject = sysinput.win32.text_inject;

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
pub var window_class_to_mode: std.StringHashMap(u8) = undefined; // No initial init

var last_content_hash: u64 = 0;

pub fn init(allocator: std.mem.Allocator) !void {
    buffer_allocator = allocator;
    buffer_manager = buffer.BufferManager.init(allocator);
    text_field_manager = detection.TextFieldManager.init(allocator);
    last_known_text = try allocator.alloc(u8, 0);

    // Initialize window class map with proper allocator
    window_class_to_mode = std.StringHashMap(u8).init(allocator);
}

fn printEscaped(text: []const u8) void {
    for (text) |c| {
        if (std.ascii.isPrint(c)) {
            debug.debugPrint("{c}", .{c});
        } else {
            debug.debugPrint("\\x{X:0>2}", .{c});
        }
    }
}

fn getWindowClassName(hwnd: ?api.HWND) ?[]const u8 {
    var class_name: [64]u8 = undefined;
    const class_len = api.GetClassNameA(hwnd, @ptrCast(&class_name), 64);
    return if (class_len > 0) class_name[0..@as(usize, @intCast(class_len))] else null;
}

/// Detect the active text field and sync with our buffer
pub fn detectActiveTextField() void {
    const active_field_found = text_field_manager.detectActiveField();

    if (active_field_found) {
        debug.debugPrint("Active text field detected\n", .{});

        // Get the text content from the field
        const text = text_field_manager.getActiveFieldText() catch |err| {
            debug.debugPrint("Failed to get text field content: {}\n", .{err});
            return;
        };
        defer buffer_allocator.free(text);

        // Update our buffer with the current text field content
        buffer_manager.resetBuffer();
        buffer_manager.insertString(text) catch |err| {
            debug.debugPrint("Failed to sync buffer with text field: {}\n", .{err});
            // Recover by inserting a smaller portion if buffer is full
            if (err == error.BufferFull and text.len > 1024) {
                debug.debugPrint("Attempting to recover by inserting smaller portion\n", .{});
                buffer_manager.resetBuffer();
                buffer_manager.insertString(text[0..1024]) catch |truncate_err| {
                    debug.debugPrint("Failed even with truncated text: {}\n", .{truncate_err});
                };
            }
        };

        debug.debugPrint("Synced buffer with text field content: \"{s}\"\n", .{text});
    } else {
        debug.debugPrint("No active text field found\n", .{});
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

    // Calculate hash for current content
    var hasher = std.hash.Wyhash.init(0);
    hasher.update(content);
    const current_hash = hasher.final();

    // If content hasn't changed (based on hash), skip expensive operations
    if (current_hash == last_content_hash) {
        return;
    }

    // Update hash and continue with normal processing
    last_content_hash = current_hash;

    debug.debugPrint("Buffer: \"", .{});
    printEscaped(content);
    debug.debugPrint("\" (len: {})\n", .{content.len});

    const word = buffer_manager.getCurrentWord() catch {
        debug.debugPrint("Error getting current word\n", .{});
        return;
    };

    // Print word with safe escaping
    debug.debugPrint("Current word: \"", .{});
    printEscaped(word);
    debug.debugPrint("\"\n", .{});

    // Process text through suggestion handler
    manager.processTextForSuggestions(content) catch |err| {
        debug.debugPrint("Error processing text for autocompletion: {}\n", .{err});
    };

    // Set current word and get suggestions
    manager.setCurrentWord(word);
    manager.getAutocompleteSuggestions() catch |err| {
        debug.debugPrint("Error getting autocompletion suggestions: {}\n", .{err});
    };

    // Show suggestions if needed
    const pos = sysinput.ui.position.getCaretPosition();
    manager.showSuggestions(content, word, pos.x, pos.y) catch |err| {
        debug.debugPrint("Error applying suggestions: {}\n", .{err});
    };
    // Check spelling
    if (word.len >= 2) {
        if (!manager.isWordCorrect(word)) {
            // Safely print the word that has a spelling error
            debug.debugPrint("Spelling error detected: \"", .{});
            for (word) |c| {
                if (std.ascii.isPrint(c)) {
                    debug.debugPrint("{c}", .{c});
                } else {
                    debug.debugPrint("\\x{X:0>2}", .{c});
                }
            }
            debug.debugPrint("\"\n", .{});

            // Get spelling suggestions if word isn't too long
            if (word.len < 15) {
                manager.getSpellingSuggestions(word) catch |err| {
                    debug.debugPrint("Error getting suggestions: {}\n", .{err});
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

/// Get current text from buffer
pub fn getCurrentText() []const u8 {
    return buffer_manager.getCurrentText();
}

/// Get current word from buffer
pub fn getCurrentWord() ![]const u8 {
    return buffer_manager.getCurrentWord();
}

/// Process char input, handling errors internally
pub fn handleCharInput(char: u8) void {
    buffer_manager.processKeyPress(char, true) catch |err| {
        debug.debugPrint("Char input error: {}\n", .{err});
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
    debug.debugPrint("Syncing buffer to text field: \"{s}\"\n", .{content});

    // Get window class to determine best method
    const focus_hwnd = api.GetFocus();
    var preferred_mode: ?SyncMode = null;

    // Get window class name once
    const class_slice = if (focus_hwnd != null)
        getWindowClassName(focus_hwnd)
    else
        null;

    // Check if we have a preferred method for this class
    if (class_slice != null) {
        debug.debugPrint("Window class: {s}\n", .{class_slice.?});

        if (window_class_to_mode.get(class_slice.?)) |mode_val| {
            preferred_mode = @as(SyncMode, @enumFromInt(mode_val));
            debug.debugPrint("Using preferred sync mode: {s}\n", .{@tagName(preferred_mode.?)});
        }
    }

    // Try methods in order of preference
    var success = false;

    // Track attempts for retry logic
    var attempt_count: u8 = 0;
    const max_attempts: u8 = 2; // Allow one retry

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

    retry: while (attempt_count < max_attempts) : (attempt_count += 1) {
        for (methods) |mode| {
            // Skip if this was already tried as the preferred method
            if (preferred_mode != null and mode == preferred_mode.?) {
                continue;
            }

            success = trySyncMethod(mode, content);
            if (success) {
                // Remember this successful method for this window class
                if (class_slice != null and focus_hwnd != null) {
                    storeSuccessfulMethod(class_slice.?, mode);
                    debug.debugPrint("Learned: {s} works best with {s}\n", .{ class_slice.?, @tagName(mode) });
                }
                return true;
            }
        }

        // If first attempt failed, wait briefly before retry
        if (attempt_count == 0) {
            debug.debugPrint("First sync attempt failed, retrying...\n", .{});
            api.Sleep(50); // Short delay before retry

            // Detect text field again in case focus changed
            if (!text_field_manager.detectActiveField()) {
                debug.debugPrint("Lost active text field during retry\n", .{});
                break :retry;
            }
        }
    }

    debug.debugPrint("Failed to update text field reliably after {d} attempts\n", .{attempt_count});
    return false;
}

/// Store successful sync method for window class
fn storeSuccessfulMethod(class_name: []const u8, mode: SyncMode) void {
    const owned_class = buffer_allocator.dupe(u8, class_name) catch {
        debug.debugPrint("Failed to allocate for class name\n", .{});
        return;
    };

    window_class_to_mode.put(owned_class, @intFromEnum(mode)) catch {
        buffer_allocator.free(owned_class);
        debug.debugPrint("Failed to store class preference\n", .{});
    };
}

/// Try a specific sync method with verification
fn trySyncMethod(mode: SyncMode, content: []const u8) bool {
    debug.debugPrint("Trying sync method: {s}\n", .{@tagName(mode)});

    // Skip empty content
    if (content.len == 0) {
        debug.debugPrint("Nothing to sync (empty content)\n", .{});
        return true; // Consider empty content sync as successful
    }

    // Track execution time for performance analysis
    const start_time = std.time.milliTimestamp();
    var success = false;

    // Handle null focus window for clipboard method early
    if (mode == .Clipboard) {
        const focus_hwnd = api.GetFocus();
        if (focus_hwnd == null) {
            debug.debugPrint("Clipboard method failed: no focus window\n", .{});
            return false;
        }

        success = text_inject.insertTextAsSelection(focus_hwnd.?, content);
    } else {
        // Execute the appropriate method
        switch (mode) {
            .Normal => {
                success = tryNormalTextFieldUpdate(content);
            },
            .Clipboard => {
                // Already handled above, but keep to avoid incomplete switch error
                unreachable;
            },
            .Simulation => {
                success = tryKeySimulation(content);

                // Key simulation needs more time to complete
                if (success) {
                    // Adaptive wait time based on content length
                    const base_wait = 50;
                    const char_wait = @min(content.len / 10, 200); // Cap at 200ms
                    api.Sleep(@intCast(base_wait + char_wait));
                }
            },
        }
    }

    // Verify success
    var verified = false;
    if (success) {
        verified = verifyTextUpdate(content);

        if (verified) {
            const elapsed = std.time.milliTimestamp() - start_time;
            debug.debugPrint("{s} succeeded and verified (took {d}ms)\n", .{ @tagName(mode), elapsed });
        } else {
            debug.debugPrint("{s} appeared to succeed but failed verification\n", .{@tagName(mode)});

            // If verification failed, wait briefly and try once more
            api.Sleep(30);
            verified = verifyTextUpdate(content);
            if (verified) {
                debug.debugPrint("Verification succeeded on second attempt\n", .{});
            }
        }
    } else {
        debug.debugPrint("{s} failed\n", .{@tagName(mode)});
    }

    return verified;
}

/// Verify text update succeeded by reading back from the control
fn verifyTextUpdate(expected: []const u8) bool {
    // Get the actual text from the control
    const actual = text_field_manager.getActiveFieldText() catch |err| {
        debug.debugPrint("Verification failed: couldn't get text from field: {}\n", .{err});
        return false;
    };
    defer buffer_allocator.free(actual);

    // Different verification strategies depending on text length
    if (expected.len < 50) {
        // For short texts, expect exact match
        const matches = std.mem.eql(u8, expected, actual);
        if (!matches) {
            debug.debugPrint("Short text verification failed:\n  Expected: \"{s}\"\n  Actual: \"{s}\"\n", .{ expected, actual });
        }
        return matches;
    } else {
        // For longer texts, use more sophisticated verification

        // 1. Check if expected is fully contained in actual
        if (std.mem.indexOf(u8, actual, expected) != null) {
            return true;
        }

        // 2. Check first 50 chars as they're most likely to be visible
        const prefix_len = @min(expected.len, 50);
        const actual_prefix = if (actual.len >= prefix_len) actual[0..prefix_len] else actual;
        const expected_prefix = expected[0..prefix_len];

        if (std.mem.eql(u8, expected_prefix, actual_prefix)) {
            debug.debugPrint("Prefix match but full text differs\n", .{});
            return true;
        }

        // 3. Calculate similarity as a percentage of matching characters
        var matching_chars: usize = 0;
        const compare_len = @min(expected.len, actual.len);

        for (0..compare_len) |i| {
            if (expected[i] == actual[i]) {
                matching_chars += 1;
            }
        }

        const similarity = @as(f32, @floatFromInt(matching_chars)) /
            @as(f32, @floatFromInt(compare_len)) * 100.0;

        // Accept if 85% or more characters match
        const high_similarity = similarity >= 85.0;

        if (!high_similarity) {
            debug.debugPrint("Long text verification failed: {d:.1}% similar\n", .{similarity});

            // Log the beginning of both strings for debugging
            const log_len = @min(@min(actual.len, expected.len), 100);
            debug.debugPrint("  Expected starts with: \"{s}\"\n  Actual starts with: \"{s}\"\n", .{ expected[0..log_len], actual[0..log_len] });
        }

        return high_similarity;
    }
}

/// Cleanup resources
pub fn deinit() void {
    buffer_manager.deinit();
    text_field_manager.deinit();

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
