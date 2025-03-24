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
        return error.NoSuggestionsNeeded;
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
    debug.debugPrint("Handler showSuggestions called with word '{s}'\n", .{current_word});
    debug.debugPrint("Have {d} suggestions to display\n", .{autocomplete_suggestions.items.len});

    // Print first few suggestions
    for (autocomplete_suggestions.items, 0..) |sugg, i| {
        if (i < 5) {
            debug.debugPrint("  Suggestion {d}: '{s}'\n", .{ i, sugg });
        }
    }

    if (autocomplete_suggestions.items.len > 0 and current_word.len >= 2) {
        // Set context
        autocomplete_ui_manager.setTextContext(current_text, current_word);

        // Show suggestions at the specified position
        try autocomplete_ui_manager.showSuggestions(autocomplete_suggestions.items, x, y);

        // Update stats
        stats.total_shown += 1;
    } else {
        debug.debugPrint("No suggestions to show (word len: {d})\n", .{current_word.len});
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

/// Enhanced suggestion word replacement that tries multiple methods
/// Returns true if successful
pub fn replaceSuggestionWord(current_word: []const u8, suggestion: []const u8) bool {
    debug.debugPrint("Replacing word '{s}' with '{s}'\n", .{ current_word, suggestion });

    // Skip if no word to replace
    if (current_word.len == 0) {
        debug.debugPrint("No current word to replace\n", .{});
        return false;
    }

    // Track metrics and timing
    stats.insertion_attempts += 1;
    const start_time = std.time.milliTimestamp();

    // Get focus window for class detection
    const focus_hwnd = api.getFocus();
    var success = false;

    // Try application-specific methods first
    if (focus_hwnd != null) {
        debug.debugPrint("Focus window: 0x{x}\n", .{@intFromPtr(focus_hwnd.?)});

        const class_name = api.safeGetClassName(focus_hwnd) catch {
            debug.debugPrint("Failed to get class name\n", .{});
            return false;
        };

        // Check parent window too
        const parent_hwnd = api.getParent(focus_hwnd.?);
        if (parent_hwnd != null) {
            const parent_class = api.safeGetClassName(parent_hwnd) catch "";
            debug.debugPrint("Parent window class: '{s}'\n", .{parent_class});
        }

        debug.debugPrint("Window class detected: '{s}'\n", .{class_name});

        // Notepad and standard edit controls
        if (std.mem.eql(u8, class_name, "Notepad") or std.mem.eql(u8, class_name, "Edit")) {
            debug.debugPrint("Detected Notepad/Edit control!\n", .{});
            // METHOD 1: Try direct key injection first (most reliable in Notepad)
            debug.debugPrint("Using key simulation for Notepad\n", .{});

            // Set window to foreground to ensure it receives input
            _ = api.setForegroundWindow(focus_hwnd.?);

            // 1. Delete the current word with backspace
            for (0..current_word.len) |_| {
                // Send backspace character by character
                var input: api.INPUT = undefined;
                input.type = api.INPUT_KEYBOARD;
                input.ki.wVk = api.VK_BACK;
                input.ki.wScan = 0;
                input.ki.dwFlags = 0; // Key down
                input.ki.time = 0;
                input.ki.dwExtraInfo = 0;
                _ = api.sendInput(1, &input, @sizeOf(api.INPUT));

                // Key up
                input.ki.dwFlags = api.KEYEVENTF_KEYUP;
                _ = api.sendInput(1, &input, @sizeOf(api.INPUT));

                api.sleep(5); // Short delay between keys
            }

            // 2. Insert the suggestion character by character
            for (suggestion) |c| {
                // Send character using unicode method
                var input: api.INPUT = undefined;
                input.type = api.INPUT_KEYBOARD;
                input.ki.wVk = 0;
                input.ki.wScan = c;
                input.ki.dwFlags = api.KEYEVENTF_UNICODE;
                input.ki.time = 0;
                input.ki.dwExtraInfo = 0;
                _ = api.sendInput(1, &input, @sizeOf(api.INPUT));

                // Key up
                input.ki.dwFlags = api.KEYEVENTF_UNICODE | api.KEYEVENTF_KEYUP;
                _ = api.sendInput(1, &input, @sizeOf(api.INPUT));

                api.sleep(5); // Short delay between keys
            }

            // 3. Insert a space
            var space_input: api.INPUT = undefined;
            space_input.type = api.INPUT_KEYBOARD;
            space_input.ki.wVk = api.VK_SPACE;
            space_input.ki.wScan = 0;
            space_input.ki.dwFlags = 0;
            space_input.ki.time = 0;
            space_input.ki.dwExtraInfo = 0;
            _ = api.sendInput(1, &space_input, @sizeOf(api.INPUT));

            // Key up
            space_input.ki.dwFlags = api.KEYEVENTF_KEYUP;
            _ = api.sendInput(1, &space_input, @sizeOf(api.INPUT));

            // 4. Update buffer manually
            resyncBufferWithTextField();

            // Add to autocomplete
            autocomplete_engine.completeWord(suggestion) catch {};

            debug.debugPrint("Key simulation succeeded\n", .{});
            success = true;

            // If key simulation succeeded, don't try other methods
            if (success) {
                stats.insertion_success += 1;
                const elapsed = std.time.milliTimestamp() - start_time;
                debug.debugPrint("Word replacement succeeded after {d}ms\n", .{elapsed});
                return true;
            }

            // If simulation fails, fall through to other methods
            debug.debugPrint("Key simulation failed, trying other methods\n", .{});
        }
        // Browser fields
        else if (std.mem.startsWith(u8, class_name, "Chrome_") or
            std.mem.eql(u8, class_name, "MozillaWindowClass"))
        {
            success = tryBrowserSpecificReplacement(focus_hwnd.?, current_word, suggestion);
        }
        // Rich edit controls
        else if (std.mem.startsWith(u8, class_name, "RICH")) {
            success = tryRichEditReplacement(focus_hwnd.?, current_word, suggestion);
        }

        // If application-specific methods failed, try general methods
        if (!success) {
            // Try direct text injection using selection approach
            if (buffer_controller.hasActiveTextField()) {
                // Make multiple attempts to select the word
                var select_attempts: u8 = 0;
                while (select_attempts < 2) : (select_attempts += 1) {
                    if (trySelectCurrentWord(focus_hwnd.?, current_word)) {
                        // Try direct insertion of the suggestion
                        if (text_inject.insertTextAsSelection(focus_hwnd.?, suggestion)) {
                            // Add a space using the same method
                            _ = text_inject.insertTextAsSelection(focus_hwnd.?, " ");

                            // Short delay to allow application to process the changes
                            api.sleep(20);

                            // Resync buffer with text field
                            resyncBufferWithTextField();

                            debug.debugPrint("Direct text injection succeeded\n", .{});
                            success = true;
                            break;
                        }
                    }

                    // Brief delay before retry
                    if (select_attempts == 0) {
                        api.sleep(30);
                    }
                }
            }
        }
    } else {
        debug.debugPrint("Not a Notepad/Edit window\n", .{});
    }

    // Fallback to backspace-and-type approach
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
        success = true;
    }

    // Update metrics
    if (success) {
        stats.insertion_success += 1;
    }

    // Calculate success rate
    stats.insertion_success_rate = @as(f32, @floatFromInt(stats.insertion_success)) /
        @as(f32, @floatFromInt(stats.insertion_attempts));

    const elapsed = std.time.milliTimestamp() - start_time;
    debug.debugPrint("Word replacement {s} after {d}ms\n", .{ if (success) "succeeded" else "failed", elapsed });

    return success;
}

/// Handle suggestion selection from the autocomplete UI
pub fn handleSuggestionSelection(suggestion: []const u8) void {
    // Get the current word being typed
    debug.debugPrint("Handling suggestion selection for: '{s}'\n", .{suggestion});

    const current_word = buffer_controller.getCurrentWord() catch {
        debug.debugPrint("Error getting current word\n", .{});
        return;
    };

    // If there's a current word, replace it with the suggestion
    if (current_word.len > 0) {
        debug.debugPrint("Current word: '{s}'\n", .{current_word});

        // Simply call replaceSuggestionWord which contains all the logic
        if (replaceSuggestionWord(current_word, suggestion)) {
            // Update stats
            stats.accepted += 1;
        }
    }
}

/// Accept the current suggestion
pub fn acceptCurrentSuggestion() void {
    if (autocomplete_ui_manager.is_visible and
        autocomplete_ui_manager.current_suggestion != null)
    {
        const suggestion = autocomplete_ui_manager.current_suggestion.?;
        debug.debugPrint("Accepting current suggestion: '{s}'\n", .{suggestion});

        // Get the current word
        const current_word = buffer_controller.getCurrentWord() catch {
            debug.debugPrint("Error getting current word\n", .{});
            return;
        };

        // Get focus window for direct manipulation
        const focus_hwnd = api.getFocus();
        if (focus_hwnd != null) {
            const class_name = api.safeGetClassName(focus_hwnd) catch "";
            debug.debugPrint("Window class for completion: '{s}'\n", .{class_name});

            // Direct fix for Notepad - bypass all other functions
            if (std.mem.eql(u8, class_name, "Notepad") or std.mem.eql(u8, class_name, "Edit")) {
                debug.debugPrint("Using direct key simulation for Notepad\n", .{});

                // Ensure the window is in foreground
                _ = api.setForegroundWindow(focus_hwnd.?);

                // 1. Delete the current word with backspace
                for (0..current_word.len) |_| {
                    var input: api.INPUT = undefined;
                    input.type = api.INPUT_KEYBOARD;
                    input.ki.wVk = api.VK_BACK;
                    input.ki.wScan = 0;
                    input.ki.dwFlags = 0;
                    input.ki.time = 0;
                    input.ki.dwExtraInfo = 0;
                    _ = api.sendInput(1, &input, @sizeOf(api.INPUT));

                    input.ki.dwFlags = api.KEYEVENTF_KEYUP;
                    _ = api.sendInput(1, &input, @sizeOf(api.INPUT));

                    api.sleep(5);
                }

                // 2. Insert the suggestion character by character
                for (suggestion) |c| {
                    var input: api.INPUT = undefined;
                    input.type = api.INPUT_KEYBOARD;
                    input.ki.wVk = 0;
                    input.ki.wScan = c;
                    input.ki.dwFlags = api.KEYEVENTF_UNICODE;
                    input.ki.time = 0;
                    input.ki.dwExtraInfo = 0;
                    _ = api.sendInput(1, &input, @sizeOf(api.INPUT));

                    input.ki.dwFlags = api.KEYEVENTF_UNICODE | api.KEYEVENTF_KEYUP;
                    _ = api.sendInput(1, &input, @sizeOf(api.INPUT));

                    api.sleep(5);
                }

                // 3. Add a space
                var space_input: api.INPUT = undefined;
                space_input.type = api.INPUT_KEYBOARD;
                space_input.ki.wVk = api.VK_SPACE;
                space_input.ki.wScan = 0;
                space_input.ki.dwFlags = 0;
                space_input.ki.time = 0;
                space_input.ki.dwExtraInfo = 0;
                _ = api.sendInput(1, &space_input, @sizeOf(api.INPUT));

                space_input.ki.dwFlags = api.KEYEVENTF_KEYUP;
                _ = api.sendInput(1, &space_input, @sizeOf(api.INPUT));

                // 4. Update buffer and statistics
                resyncBufferWithTextField();
                autocomplete_engine.completeWord(suggestion) catch {};
                stats.accepted += 1;

                debug.debugPrint("Direct key simulation completed\n", .{});

                // Hide suggestions and return
                hideSuggestions();
                return;
            }
        }

        // For other applications, use normal path
        handleSuggestionSelection(suggestion);
        hideSuggestions();
    }
}

/// Hide suggestions UI
pub fn hideSuggestions() void {
    autocomplete_ui_manager.hideSuggestions();
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

/// Special handler for Notepad/Edit completion
fn handleNotepadCompletion(hwnd: api.HWND, current_word: []const u8, suggestion: []const u8) bool {
    debug.debugPrint("Using enhanced Notepad completion handler\n", .{});

    // APPROACH 1: Precise selection method for Notepad

    // First, get current selection
    const selection = api.sendMessage(hwnd, api.EM_GETSEL, 0, 0);
    const sel_u64: u64 = @bitCast(selection);
    const sel_start: u32 = @truncate(sel_u64 & 0xFFFF);
    const sel_end: u32 = @truncate((sel_u64 >> 16) & 0xFFFF);

    debug.debugPrint("Current selection: {d}-{d}\n", .{ sel_start, sel_end });

    // Calculate positions for word replacement
    const caret_pos = @max(sel_start, sel_end); // Use the end of selection
    const word_start = if (caret_pos >= current_word.len)
        caret_pos - current_word.len
    else
        0;

    debug.debugPrint("Calculated word bounds: {d}-{d}\n", .{ word_start, caret_pos });

    // IMPORTANT: Select the word first
    _ = api.sendMessage(hwnd, api.EM_SETSEL, word_start, caret_pos);

    // Verify selection worked by checking selection again
    const new_selection = api.sendMessage(hwnd, api.EM_GETSEL, 0, 0);
    const new_sel_u64: u64 = @bitCast(new_selection);
    const new_start: u32 = @truncate(new_sel_u64 & 0xFFFF);
    const new_end: u32 = @truncate((new_sel_u64 >> 16) & 0xFFFF);

    debug.debugPrint("New selection after EM_SETSEL: {d}-{d}\n", .{ new_start, new_end });

    // Only continue if we have a valid selection
    if (new_start != new_end) {
        // Create null-terminated buffer for the replacement
        const buffer = std.heap.page_allocator.allocSentinel(u8, suggestion.len, 0) catch {
            debug.debugPrint("Failed to allocate buffer for suggestion\n", .{});
            return false;
        };
        defer std.heap.page_allocator.free(buffer);

        @memcpy(buffer, suggestion);

        // Replace the selected text
        const ptr_value: usize = @intFromPtr(buffer.ptr);
        const result = api.sendMessage(hwnd, api.EM_REPLACESEL, 1, @as(api.LPARAM, @intCast(ptr_value)));

        if (result != 0) {
            // Add a space after the suggestion
            var space_buffer = std.heap.page_allocator.allocSentinel(u8, 1, 0) catch {
                return false;
            };
            defer std.heap.page_allocator.free(space_buffer);
            space_buffer[0] = ' ';

            const space_ptr: usize = @intFromPtr(space_buffer.ptr);
            _ = api.sendMessage(hwnd, api.EM_REPLACESEL, 1, @as(api.LPARAM, @intCast(space_ptr)));

            // Resync our buffer with the edited text
            resyncBufferWithTextField();

            // Add the word to the autocomplete engine's vocabulary
            autocomplete_engine.completeWord(suggestion) catch |err| {
                debug.debugPrint("Error adding to vocabulary: {}\n", .{err});
            };

            debug.debugPrint("Notepad direct replacement succeeded\n", .{});
            return true;
        } else {
            debug.debugPrint("EM_REPLACESEL failed\n", .{});
        }
    } else {
        debug.debugPrint("Failed to select text range\n", .{});
    }

    // APPROACH 2: Try clipboard approach if direct selection failed
    debug.debugPrint("Trying clipboard approach for Notepad\n", .{});

    // First select the current word precisely
    const word_len: api.DWORD = @intCast(current_word.len);
    const actual_start = if (sel_end >= word_len) sel_end - word_len else 0;
    _ = api.sendMessage(hwnd, api.EM_SETSEL, actual_start, sel_end);

    // Now try clipboard insertion
    if (text_inject.insertViaClipboard(hwnd, suggestion)) {
        // Add space
        _ = text_inject.insertViaClipboard(hwnd, " ");
        // Resync buffer
        resyncBufferWithTextField();
        return true;
    }

    return false;
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

/// Try selecting the current word in the text field
fn trySelectCurrentWord(hwnd: api.HWND, word: []const u8) bool {
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

    // For more reliable word location, get the text content
    const text_length = api.sendMessage(hwnd, api.WM_GETTEXTLENGTH, 0, 0);
    if (text_length > 0) {
        const buffer_size = @min(text_length + 1, 4096);
        const text_buffer = std.heap.page_allocator.allocSentinel(u8, @intCast(buffer_size), 0) catch {
            return false;
        };
        defer std.heap.page_allocator.free(text_buffer);

        const text_ptr: usize = @intFromPtr(text_buffer.ptr);
        const buffer_size_u: usize = @intCast(buffer_size);
        const text_result = api.sendMessage(hwnd, api.WM_GETTEXT, buffer_size_u, @intCast(text_ptr));

        if (text_result > 0) {
            // Look for word near cursor position
            const cursor_pos = sel_end;
            const search_start = if (cursor_pos > 100) cursor_pos - 100 else 0;
            const search_end = @min(cursor_pos + 100, text_result);

            var i: u32 = search_start;
            while (i < search_end) : (i += 1) {
                // Check if this position could be the start of our word
                if (i == 0 or !isWordChar(text_buffer[i - 1])) {
                    // Check if word matches here
                    if (i + word.len <= search_end) {
                        var matches = true;
                        for (0..word.len) |j| {
                            if (text_buffer[i + j] != word[j]) {
                                matches = false;
                                break;
                            }
                        }

                        if (matches) {
                            // Found the word! Select it
                            _ = api.sendMessage(hwnd, api.EM_SETSEL, i, @as(api.LPARAM, @intCast(i + word.len)));
                            debug.debugPrint("Found word at position {}-{}\n", .{ i, i + word.len });
                            return true;
                        }
                    }
                }
            }
        }
    }

    // METHOD 3: Simple fallback - use whatever was found
    _ = api.sendMessage(hwnd, api.EM_SETSEL, sel_start, sel_end);
    return sel_start != sel_end;
}

/// Add a word to the autocompletion engine's vocabulary
pub fn addWordToVocabulary(word: []const u8) !void {
    try autocomplete_engine.addWord(word);
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
