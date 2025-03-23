const std = @import("std");
const sysinput = @import("sysinput.zig");

const api = sysinput.win32.api;
const spellcheck = sysinput.text.spellcheck;
const autocomplete = sysinput.text.autocomplete;
const suggestion_ui = sysinput.ui.suggestion_ui;
const text_inject = sysinput.win32.text_inject;
const buffer_controller = sysinput.buffer_controller;
const dictionary = sysinput.text.dictionary;
const debug = sysinput.core.debug;
const detection = sysinput.input.text_field;
const position = sysinput.ui.position;

/// Global variables for allocator access
var gpa_allocator: std.mem.Allocator = undefined;

/// Global spellchecker
pub var spell_checker: spellcheck.SpellChecker = undefined;

/// Global autocompletion engine
pub var autocomplete_engine: autocomplete.AutocompleteEngine = undefined;

/// List for storing word suggestions
pub var suggestions: std.ArrayList([]const u8) = undefined;

/// Autocompletion suggestions list
pub var autocomplete_suggestions: std.ArrayList([]const u8) = undefined;

/// Global UI for autocompletion suggestions
pub var autocomplete_ui_manager: suggestion_ui.AutocompleteUI = undefined;

/// Last word processed for suggestions
pub var last_word_processed: []const u8 = "";

/// Stats for tracking suggestion usage
pub var stats = struct {
    /// Total suggestions shown
    total_shown: u32 = 0,
    /// Suggestions accepted
    accepted: u32 = 0,
    /// Success rate for insertions
    insertion_success_rate: f32 = 0.0,
    /// Total insertion attempts
    insertion_attempts: u32 = 0,
    /// Successful insertions
    insertion_success: u32 = 0,
}{};

/// Initialize suggestion handling components
pub fn init(allocator: std.mem.Allocator, module_instance: anytype) !void {
    gpa_allocator = allocator;

    // Initialize spellchecker
    spell_checker = try spellcheck.SpellChecker.init(allocator);

    // Initialize suggestions lists
    suggestions = std.ArrayList([]const u8).init(allocator);
    autocomplete_suggestions = std.ArrayList([]const u8).init(allocator);

    // Initialize autocompletion engine
    autocomplete_engine = try autocomplete.AutocompleteEngine.init(allocator, &spell_checker.dictionary);

    // Initialize UI
    autocomplete_ui_manager = try suggestion_ui.AutocompleteUI.init(allocator, module_instance);

    // Set callback
    autocomplete_ui_manager.setSelectionCallback(handleSuggestionSelection);
}

/// Deinitialize components
pub fn deinit() void {
    // Free resources
    for (suggestions.items) |item| {
        gpa_allocator.free(item);
    }
    suggestions.deinit();

    for (autocomplete_suggestions.items) |item| {
        gpa_allocator.free(item);
    }
    autocomplete_suggestions.deinit();

    if (last_word_processed.len > 0) {
        gpa_allocator.free(last_word_processed);
    }

    spell_checker.deinit();
    autocomplete_engine.deinit();
    autocomplete_ui_manager.deinit();
}

/// Process a text for autocomplete suggestions
pub fn processTextForSuggestions(text: []const u8) !void {
    try autocomplete_engine.processText(text);
}

/// Set current word for autocompletion
pub fn setCurrentWord(word: []const u8) void {
    autocomplete_engine.setCurrentWord(word);
}

/// Get autocompletion suggestions
pub fn getAutocompleteSuggestions() !void {
    // Skip processing if the word hasn't changed
    if (std.mem.eql(u8, autocomplete_engine.current_word, last_word_processed) and
        autocomplete_suggestions.items.len > 0)
    {
        return;
    }

    // Store the current word as the last processed
    const current_word = autocomplete_engine.current_word;
    const owned_word = try gpa_allocator.dupe(u8, current_word);
    if (last_word_processed.len > 0) {
        gpa_allocator.free(last_word_processed);
    }
    last_word_processed = owned_word;

    // Clear existing suggestions
    for (autocomplete_suggestions.items) |item| {
        gpa_allocator.free(item);
    }
    autocomplete_suggestions.clearRetainingCapacity();

    // Get new suggestions
    try autocomplete_engine.getSuggestions(&autocomplete_suggestions);
}

/// Check if a word is spelled correctly
pub fn isWordCorrect(word: []const u8) bool {
    return spell_checker.isCorrect(word);
}

/// Get spelling suggestions for a word
pub fn getSpellingSuggestions(word: []const u8) !void {
    // Clear existing suggestions
    for (suggestions.items) |item| {
        gpa_allocator.free(item);
    }
    suggestions.clearRetainingCapacity();

    // Get suggestions
    try spell_checker.getSuggestions(word, &suggestions);
}

/// Show suggestions in UI
pub fn showSuggestions(current_text: []const u8, current_word: []const u8, x: i32, y: i32) !void {
    if (autocomplete_suggestions.items.len > 0 and current_word.len >= 2) {
        // Set context
        autocomplete_ui_manager.setTextContext(current_text, current_word);

        // Show suggestions at the specified position
        try autocomplete_ui_manager.showSuggestions(autocomplete_suggestions.items, x, y);

        // Update stats
        stats.total_shown += 1;
    } else {
        hideSuggestions();
    }
}

/// Update the position of suggestions if visible
pub fn updateSuggestionPosition() void {
    if (autocomplete_ui_manager.is_visible) {
        const pos = position.getCaretPosition();
        if (pos.x != 0 or pos.y != 0) {
            // Offset below caret
            autocomplete_ui_manager.updatePosition(pos.x, pos.y + 20);
        }
    }
}

/// Hide suggestions UI
pub fn hideSuggestions() void {
    autocomplete_ui_manager.hideSuggestions();
}

/// Enhanced suggestion word replacement that tries multiple methods
pub fn replaceSuggestionWord(current_word: []const u8, suggestion: []const u8) bool {
    debug.debugPrint("Replacing word '{s}' with '{s}'\n", .{ current_word, suggestion });

    // Keep track of attempts
    stats.insertion_attempts += 1;

    // Get focus window for class detection
    const focus_hwnd = api.GetFocus();
    var success = false;

    if (focus_hwnd != null) {
        var class_name: [64]u8 = [_]u8{0} ** 64;
        const class_ptr: [*:0]u8 = @ptrCast(&class_name);
        const class_len = detection.GetClassNameA(focus_hwnd.?, class_ptr, 64);

        var class_slice: []const u8 = "";
        if (class_len > 0) {
            class_slice = class_name[0..@intCast(class_len)];
            debug.debugPrint("Replacing in window class: {s}\n", .{class_slice});
        }

        // Add special handling for Notepad
        if (std.mem.eql(u8, class_slice, "Notepad") or std.mem.eql(u8, class_slice, "Edit")) {
            // For Notepad, first try a direct selection approach
            debug.debugPrint("Using Notepad-specific replacement method\n", .{});

            // Get cursor selection
            const selection = api.SendMessageA(focus_hwnd.?, api.EM_GETSEL, 0, 0);
            const sel_u64: u64 = @bitCast(selection);
            const sel_end: u32 = @truncate((sel_u64 >> 16) & 0xFFFF);

            // Calculate where the word should start
            const start_pos = if (sel_end >= current_word.len)
                sel_end - current_word.len
            else
                0;

            debug.debugPrint("Selecting word from position {d} to {d}\n", .{ start_pos, sel_end });

            // Explicitly select the word
            const start_wp: api.WPARAM = @intCast(start_pos);
            const end_lp: api.LPARAM = @intCast(sel_end);
            _ = api.SendMessageA(focus_hwnd.?, api.EM_SETSEL, start_wp, end_lp);

            // Wait briefly for selection to take effect
            api.Sleep(10);

            // Create buffer with null terminator for the replacement
            const buffer = std.heap.page_allocator.allocSentinel(u8, suggestion.len, 0) catch {
                debug.debugPrint("Failed to allocate buffer\n", .{});
                return false;
            };
            defer std.heap.page_allocator.free(buffer);

            @memcpy(buffer, suggestion);

            // Try replacing the selection
            const ptr_value: usize = @intFromPtr(buffer.ptr);
            const result = api.SendMessageA(focus_hwnd.?, api.EM_REPLACESEL, 1, @as(api.LPARAM, @intCast(ptr_value)));

            if (result != 0) {
                // Add a space
                var space_buffer = std.heap.page_allocator.allocSentinel(u8, 1, 0) catch {
                    return false;
                };
                defer std.heap.page_allocator.free(space_buffer);
                space_buffer[0] = ' ';

                const space_ptr: usize = @intFromPtr(space_buffer.ptr);
                _ = api.SendMessageA(focus_hwnd.?, api.EM_REPLACESEL, 1, @as(api.LPARAM, @intCast(space_ptr)));

                // Resync our buffer
                resyncBufferWithTextField();

                // Add word to autocomplete engine
                autocomplete_engine.completeWord(suggestion) catch {};

                debug.debugPrint("Notepad direct replacement succeeded\n", .{});
                stats.insertion_success += 1;
                return true;
            }

            debug.debugPrint("Notepad direct replacement failed\n", .{});
        }

        // METHOD 1: Try direct text injection using selection approach
        if (buffer_controller.hasActiveTextField()) {
            if (trySelectCurrentWord(focus_hwnd.?, current_word)) {
                // Try direct insertion of the suggestion
                if (text_inject.insertTextAsSelection(focus_hwnd.?, suggestion)) {
                    // Add a space using the same method
                    _ = text_inject.insertTextAsSelection(focus_hwnd.?, " ");

                    // Resync our buffer with the field
                    resyncBufferWithTextField();

                    // Add to autocomplete engine
                    autocomplete_engine.completeWord(suggestion) catch |err| {
                        debug.debugPrint("Error adding word to autocomplete: {}\n", .{err});
                    };

                    debug.debugPrint("Direct text injection succeeded\n", .{});
                    stats.insertion_success += 1;
                    success = true;
                }
            }
        }

        // If direct injection failed, try application-specific methods

        if (!success) {
            // Special handling for particular application classes
            if (std.mem.eql(u8, class_slice, "Chrome_WidgetWin_1") or
                std.mem.eql(u8, class_slice, "MozillaWindowClass"))
            {
                // Browser text fields often work better with clipboard method
                success = tryBrowserSpecificReplacement(focus_hwnd.?, current_word, suggestion);
            } else if (std.mem.startsWith(u8, class_slice, "RICHEDIT")) {
                // Rich edit controls need special handling
                success = tryRichEditReplacement(focus_hwnd.?, current_word, suggestion);
            }
        }
    }

    // METHOD 2: Try backspace-and-type approach as fallback if all else failed
    if (!success) {
        debug.debugPrint("Using backspace-and-type approach\n", .{});

        // Delete the current word by backspacing
        var i: usize = 0;
        while (i < current_word.len) : (i += 1) {
            buffer_controller.processBackspace() catch |err| {
                debug.debugPrint("Backspace error: {}\n", .{err});
                return false;
            };
        }

        // Insert the suggestion
        buffer_controller.insertString(suggestion) catch |err| {
            debug.debugPrint("Suggestion insertion error: {}\n", .{err});
            return false;
        };

        // Add a space after the suggestion
        buffer_controller.insertString(" ") catch |err| {
            debug.debugPrint("Space insertion error: {}\n", .{err});
        };

        // Add to autocomplete engine
        autocomplete_engine.completeWord(suggestion) catch |err| {
            debug.debugPrint("Error adding word to autocomplete: {}\n", .{err});
        };

        debug.debugPrint("Backspace-and-type approach succeeded\n", .{});
        stats.insertion_success += 1;
        success = true;
    }

    // Calculate success rate
    stats.insertion_success_rate = @as(f32, @floatFromInt(stats.insertion_success)) /
        @as(f32, @floatFromInt(stats.insertion_attempts));

    return success;
}

/// Check if a character is part of a word
fn isWordChar(c: u8) bool {
    // Allow letters, numbers, underscore, and apostrophe (for contractions)
    return std.ascii.isAlphanumeric(c) or c == '_' or c == '\'';
}

/// Resync the buffer with the text field after modification
fn resyncBufferWithTextField() void {
    if (!buffer_controller.hasActiveTextField()) {
        return;
    }

    const text = buffer_controller.getActiveFieldText() catch |err| {
        debug.debugPrint("Failed to get updated text: {}\n", .{err});
        return;
    };
    defer gpa_allocator.free(text);

    buffer_controller.resetBuffer();
    buffer_controller.insertString(text) catch |err| {
        debug.debugPrint("Failed to update buffer: {}\n", .{err});
    };
}

/// Handle suggestion selection from the autocomplete UI
pub fn handleSuggestionSelection(suggestion: []const u8) void {
    // Get the current word being typed
    const current_word = buffer_controller.getCurrentWord() catch {
        debug.debugPrint("Error getting current word\n", .{});
        return;
    };

    // If there's a current word, replace it with the suggestion
    if (current_word.len > 0) {
        if (replaceSuggestionWord(current_word, suggestion)) {
            // Update stats
            stats.accepted += 1;

            // Hide suggestions after successful selection
            hideSuggestions();
        }
    }
}

/// Check if suggestions UI is visible
pub fn isSuggestionUIVisible() bool {
    return autocomplete_ui_manager.is_visible;
}

/// Navigate to previous suggestion
pub fn navigateToPreviousSuggestion() void {
    // Move to previous suggestion
    const new_index = if (autocomplete_ui_manager.selected_index <= 0)
        @as(i32, @intCast(autocomplete_suggestions.items.len - 1))
    else
        autocomplete_ui_manager.selected_index - 1;

    autocomplete_ui_manager.selectSuggestion(new_index);
    debug.debugPrint("Selected previous suggestion (index {})\n", .{new_index});
}

/// Navigate to next suggestion
pub fn navigateToNextSuggestion() void {
    // Move to next suggestion
    const new_index = if (autocomplete_ui_manager.selected_index >= autocomplete_suggestions.items.len - 1)
        0
    else
        autocomplete_ui_manager.selected_index + 1;

    autocomplete_ui_manager.selectSuggestion(new_index);
    debug.debugPrint("Selected next suggestion (index {})\n", .{new_index});
}

/// Accept the current suggestion
pub fn acceptCurrentSuggestion() void {
    if (autocomplete_ui_manager.is_visible and
        autocomplete_ui_manager.current_suggestion != null)
    {
        const suggestion = autocomplete_ui_manager.current_suggestion.?;
        debug.debugPrint("Accepting current suggestion: '{s}'\n", .{suggestion});

        // Detect special characters in suggestion that might cause issues
        var has_special_chars = false;
        for (suggestion) |c| {
            if (c < 32 or c > 126) {
                has_special_chars = true;
                break;
            }
        }

        // Use resilient method for special characters
        if (has_special_chars) {
            debug.debugPrint("Suggestion contains special characters - using robust insertion\n", .{});

            // Get the current word first
            const current_word = buffer_controller.getCurrentWord() catch "";

            // Replace directly through buffer controller to avoid character issues
            if (current_word.len > 0) {
                // Delete the current word
                var i: usize = 0;
                while (i < current_word.len) : (i += 1) {
                    buffer_controller.processBackspace() catch {};
                }

                // Insert the suggestion
                buffer_controller.insertString(suggestion) catch {};
                buffer_controller.insertString(" ") catch {};

                // Hide suggestions
                hideSuggestions();
                return;
            }
        }

        // Standard case: use the callback
        handleSuggestionSelection(suggestion);
    }
}

/// Get selected suggestion index
pub fn getSelectedSuggestionIndex() i32 {
    return autocomplete_ui_manager.selected_index;
}

/// Select a suggestion by index
pub fn selectSuggestion(index: i32) void {
    autocomplete_ui_manager.selectSuggestion(index);
}

/// Get number of available suggestions
pub fn getSuggestionCount() usize {
    return autocomplete_suggestions.items.len;
}

/// Try browser-specific text replacement
fn tryBrowserSpecificReplacement(hwnd: api.HWND, current_word: []const u8, suggestion: []const u8) bool {
    // For browsers, clipboard method often works best
    debug.debugPrint("Using browser-specific replacement method\n", .{});

    // First try to select the current word
    if (!trySelectCurrentWord(hwnd, current_word)) {
        // If selection fails, try selecting with keyboard shortcut
        // Simulate Ctrl+Left to move to word start
        simulateKeyPress(api.VK_CONTROL, true);
        simulateKeyPress(api.VK_LEFT, true);
        simulateKeyPress(api.VK_LEFT, false);
        simulateKeyPress(api.VK_CONTROL, false);

        // Add Shift for selection
        simulateKeyPress(api.VK_SHIFT, true);
        simulateKeyPress(api.VK_CONTROL, true);
        simulateKeyPress(api.VK_RIGHT, true);
        simulateKeyPress(api.VK_RIGHT, false);
        simulateKeyPress(api.VK_CONTROL, false);
        simulateKeyPress(api.VK_SHIFT, false);

        api.Sleep(20); // Brief delay
    }

    // Use clipboard for replacement
    return text_inject.insertTextAsSelection(hwnd, suggestion);
}

/// Try rich edit specific text replacement
fn tryRichEditReplacement(hwnd: api.HWND, current_word: []const u8, suggestion: []const u8) bool {
    debug.debugPrint("Using rich edit specific replacement method\n", .{});

    // Rich edit controls sometimes work better with direct WM_SETTEXT after selection
    // First try to select the current word
    if (trySelectCurrentWord(hwnd, current_word)) {
        // Get the text length
        const text_length = api.SendMessageA(hwnd, api.WM_GETTEXTLENGTH, 0, 0);
        if (text_length <= 0) return false;

        // Get the full text
        const buffer_size = @min(text_length + 1, 4096);
        var text_buffer = std.heap.page_allocator.allocSentinel(u8, @intCast(buffer_size), 0) catch {
            return false;
        };
        defer std.heap.page_allocator.free(text_buffer);

        const text_ptr: usize = @intFromPtr(text_buffer.ptr);
        const buffer_size_u: usize = @intCast(buffer_size);
        const text_result = api.SendMessageA(hwnd, api.WM_GETTEXT, buffer_size_u, @intCast(text_ptr));

        if (text_result > 0) {
            // Get current selection
            const selection = api.SendMessageA(hwnd, api.EM_GETSEL, 0, 0);
            const sel_u64: u64 = @bitCast(selection);
            const sel_start: u32 = @truncate(sel_u64 & 0xFFFF);
            const sel_end: u32 = @truncate((sel_u64 >> 16) & 0xFFFF);

            // Create replacement text
            const result_usize: usize = @intCast(text_result);
            const sel_diff: usize = @intCast(sel_end - sel_start);
            var new_text = std.heap.page_allocator.allocSentinel(u8, result_usize - sel_diff + suggestion.len, 0) catch {
                return false;
            };
            defer std.heap.page_allocator.free(new_text);

            // Copy text before selection
            if (sel_start > 0) {
                @memcpy(new_text[0..sel_start], text_buffer[0..sel_start]);
            }

            // Insert suggestion
            @memcpy(new_text[sel_start .. sel_start + suggestion.len], suggestion);

            // Copy text after selection
            if (sel_end < text_result) {
                const after_len = text_result - sel_end;
                _ = after_len; // autofix
                const sel_end_usize: usize = @intCast(sel_end);
                const text_result_usize: usize = @intCast(text_result);
                @memcpy(new_text[sel_start + suggestion.len ..], text_buffer[sel_end_usize..text_result_usize]);
            }

            // Set as new text
            const new_ptr: usize = @intFromPtr(new_text.ptr);
            _ = api.SendMessageA(hwnd, api.WM_SETTEXT, 0, @intCast(new_ptr));

            // Position cursor after inserted suggestion
            const new_pos = sel_start + suggestion.len;
            const new_pos_wparam: api.WPARAM = @intCast(new_pos);
            const new_pos_lparam: api.LPARAM = @intCast(new_pos);
            _ = api.SendMessageA(hwnd, api.EM_SETSEL, new_pos_wparam, new_pos_lparam);

            return true;
        }
    }

    return false;
}

/// Simulate a key press/release
fn simulateKeyPress(vk: u8, is_down: bool) void {
    var input: api.INPUT = undefined;
    input.type = api.INPUT_KEYBOARD;
    input.ki.wVk = vk;
    input.ki.wScan = 0;
    input.ki.dwFlags = if (is_down) 0 else api.KEYEVENTF_KEYUP;
    input.ki.time = 0;
    input.ki.dwExtraInfo = 0;

    _ = api.SendInput(1, &input, @sizeOf(api.INPUT));
}

/// Try to find and select the current word in the text field
fn trySelectCurrentWord(hwnd: api.HWND, word: []const u8) bool {
    // METHOD 1: Use selection information
    const selection = api.SendMessageA(hwnd, api.EM_GETSEL, 0, 0);
    const sel_u64: u64 = @bitCast(selection);
    const sel_start: u32 = @truncate(sel_u64 & 0xFFFF);
    const sel_end: u32 = @truncate((sel_u64 >> 16) & 0xFFFF);

    // If we have a valid selection
    if (sel_start <= sel_end) {
        // If selection is a point (cursor), find word boundaries
        if (sel_start == sel_end) {
            // Get the text around this position
            const text_length = api.SendMessageA(hwnd, api.WM_GETTEXTLENGTH, 0, 0);
            if (text_length > 0) {
                const buffer_size = @min(text_length + 1, 4096);
                var text_buffer = std.heap.page_allocator.allocSentinel(u8, @intCast(buffer_size), 0) catch {
                    return false;
                };
                defer std.heap.page_allocator.free(text_buffer);

                const text_ptr: usize = @intFromPtr(text_buffer.ptr);
                const buffer_size_u: usize = @intCast(buffer_size);
                const text_result = api.SendMessageA(hwnd, api.WM_GETTEXT, buffer_size_u, @intCast(text_ptr));

                if (text_result > 0) {
                    // Try to find boundaries of current word
                    var word_start = sel_start;
                    var word_end = sel_end;

                    // Improved: Try both approaches - from cursor backward or look for the
                    // exact word in surrounding text

                    // Search backward for word start
                    var found_by_search = false;
                    if (sel_start > 0) {
                        var i = sel_start;
                        while (i > 0) : (i -= 1) {
                            const c = text_buffer[i - 1];
                            if (!isWordChar(c)) {
                                break;
                            }
                            word_start = i - 1;
                        }
                    }

                    // Search forward for word end
                    if (sel_end < text_result) {
                        var i = sel_end;
                        while (i < text_result) : (i += 1) {
                            const c = text_buffer[i];
                            if (!isWordChar(c)) {
                                break;
                            }
                            word_end = i + 1;
                        }
                    }

                    // Check if we found a word that matches what we're looking for
                    if (word_end > word_start) {
                        const found_word = text_buffer[word_start..word_end];

                        // Verify that this is the word we're looking for
                        if (std.mem.eql(u8, found_word, word)) {
                            // Select the word
                            _ = api.SendMessageA(hwnd, api.EM_SETSEL, word_start, word_end);
                            found_by_search = true;
                            return true;
                        }
                    }

                    // If we couldn't find by looking at cursor position, search for the word
                    // in the surrounding text (more reliable for some applications)
                    if (!found_by_search) {
                        // Look for the word in the general vicinity of the cursor
                        const search_start = if (sel_start > 20) sel_start - 20 else 0;
                        const search_end = if (sel_end + 20 < text_result) sel_end + 20 else text_result;
                        const search_start_usize: usize = @intCast(search_start);
                        const search_end_usize: usize = @intCast(search_end);
                        const search_area = text_buffer[search_start_usize..search_end_usize];

                        var start_pos: ?usize = null;
                        for (search_area, 0..) |_, i| {
                            // Check if this is a possible word start
                            if (i == 0 or !isWordChar(search_area[i - 1])) {
                                // See if word matches starting here
                                if (i + word.len <= search_area.len) {
                                    const possible_match = search_area[i .. i + word.len];
                                    if (std.mem.eql(u8, possible_match, word)) {
                                        // Found exact match
                                        start_pos = search_start + i;
                                        break;
                                    }
                                }
                            }
                        }

                        if (start_pos) |pos| {
                            // Found the exact word, select it

                            const pos_wparam: api.WPARAM = @intCast(pos);
                            const end_pos_lparam: api.LPARAM = @intCast(pos + word.len);
                            _ = api.SendMessageA(hwnd, api.EM_SETSEL, pos_wparam, end_pos_lparam);
                        }
                    }
                }
            }
        }

        // If we have a non-empty selection, check if it's the word we're looking for
        if (sel_end > sel_start) {
            const selection_length = sel_end - sel_start;
            if (selection_length == word.len) {
                // The selection length matches our word, assume it's correct
                return true;
            }
        }
    }

    // METHOD 2: Simple heuristic - just try positioning based on cursor and word length
    if (sel_start == sel_end) {
        // Assume the cursor is at the end of the word
        const estimated_start = if (sel_end >= word.len) sel_end - word.len else 0;
        _ = api.SendMessageA(hwnd, api.EM_SETSEL, estimated_start, sel_end);
        return true;
    }

    return false;
}

/// Add a word to the autocompletion engine's vocabulary
pub fn addWordToVocabulary(word: []const u8) !void {
    try autocomplete_engine.addWord(word);
}
