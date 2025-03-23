const std = @import("std");
const common = @import("../win32/common.zig");
const suggestion_window = @import("suggestion_window.zig");
const text_completion = @import("text_completion.zig");
const ui_utils = @import("ui_utils.zig");

/// Inline completion UI manager
pub const AutocompleteUI = struct {
    /// Current suggestions
    suggestions: [][]const u8,
    /// Selected suggestion index
    selected_index: i32,
    /// Allocator for operations
    allocator: std.mem.Allocator,
    /// Whether suggestions are active
    is_visible: bool,
    /// Current text in the control
    current_text: []const u8,
    /// Current partial word
    current_word: []const u8,
    /// Current best suggestion
    current_suggestion: ?[]const u8,
    /// Callback for completing a suggestion
    selection_callback: ?*const fn ([]const u8) void,
    /// Window handle for suggestion UI
    suggestion_window: ?common.HWND,
    /// Module instance
    instance: common.HINSTANCE,
    /// Window class atom for suggestion window
    window_class_atom: common.ATOM,

    /// Initialize the inline completion
    pub fn init(allocator: std.mem.Allocator, instance: common.HINSTANCE) !AutocompleteUI {
        // Register window class for suggestions
        const atom = try suggestion_window.registerSuggestionWindowClass(instance);

        return AutocompleteUI{
            .suggestions = &[_][]const u8{},
            .selected_index = -1,
            .allocator = allocator,
            .is_visible = false,
            .current_text = "",
            .current_word = "",
            .current_suggestion = null,
            .selection_callback = null,
            .suggestion_window = null,
            .instance = instance,
            .window_class_atom = atom,
        };
    }

    /// Process suggestions for the current text
    pub fn showSuggestions(self: *AutocompleteUI, suggestions: [][]const u8, x: i32, y: i32) !void {
        self.suggestions = suggestions;
        self.selected_index = 0;
        suggestion_window.g_ui_state.suggestions = suggestions;
        suggestion_window.g_ui_state.selected_index = 0;

        // If we have suggestions, mark as visible and try to apply the first one
        if (suggestions.len > 0) {
            self.is_visible = true;
            self.current_suggestion = suggestions[0];

            // Try multiple approaches for inline completion
            if (!text_completion.tryDirectCompletion(self.current_word, self.current_suggestion.?)) {
                // If direct completion fails, try using selection-based approach
                _ = text_completion.trySelectionCompletion(self.current_word, self.current_suggestion.?);
            }

            // Show UI suggestion list near cursor position
            try self.showSuggestionUI(x, y);
        } else {
            self.hideSuggestions();
        }
    }

    /// Show the suggestion UI window
    fn showSuggestionUI(self: *AutocompleteUI, x: i32, y: i32) !void {
        // Only attempt to create or show the window if we have suggestions
        if (self.suggestions.len == 0) {
            return;
        }

        // Get position for suggestions
        var suggested_pos = common.POINT{ .x = x, .y = y };

        // Only use provided coordinates if they're non-zero
        if (x == 0 and y == 0) {
            // Get intelligent position based on caret or text field
            suggested_pos = ui_utils.getCaretPosition();
        }

        // Adjust position to appear just below the text insertion point
        suggested_pos.y += 20;

        std.debug.print("Showing suggestion UI at {}, {}\n", .{ suggested_pos.x, suggested_pos.y });

        // Calculate window size based on suggestions
        const size = ui_utils.calculateSuggestionWindowSize(self.suggestions, suggestion_window.SUGGESTION_FONT_HEIGHT, suggestion_window.WINDOW_PADDING);

        // Create window if it doesn't exist
        if (self.suggestion_window == null) {
            std.debug.print("Creating suggestion window\n", .{});

            const window = common.CreateWindowExA(
                common.WS_EX_TOPMOST | common.WS_EX_TOOLWINDOW | common.WS_EX_NOACTIVATE,
                suggestion_window.SUGGESTION_WINDOW_CLASS,
                "Suggestions\x00",
                common.WS_POPUP | common.WS_BORDER,
                suggested_pos.x,
                suggested_pos.y,
                size.width,
                size.height,
                null, // No parent
                null, // No menu
                self.instance,
                null, // No lpParam
            );

            if (window == null) {
                std.debug.print("Failed to create suggestion window\n", .{});
                return error.WindowCreationFailed;
            }

            self.suggestion_window = window;
        } else {
            // Reposition existing window
            _ = common.SetWindowPos(
                self.suggestion_window.?,
                common.HWND_TOPMOST,
                suggested_pos.x,
                suggested_pos.y,
                size.width,
                size.height,
                common.SWP_SHOWWINDOW,
            );
        }

        // Show the window
        _ = common.ShowWindow(self.suggestion_window.?, common.SW_SHOWNOACTIVATE);
        _ = common.UpdateWindow(self.suggestion_window.?);
    }

    /// Set current text context
    pub fn setTextContext(self: *AutocompleteUI, full_text: []const u8, current_word: []const u8) void {
        self.current_text = full_text;
        self.current_word = current_word;
    }

    /// Hide the suggestions
    pub fn hideSuggestions(self: *AutocompleteUI) void {
        self.is_visible = false;
        self.current_suggestion = null;

        // Hide the UI window if it exists
        if (self.suggestion_window != null) {
            _ = common.ShowWindow(self.suggestion_window.?, common.SW_HIDE);
        }
    }

    /// Set the callback for suggestion selection
    pub fn setSelectionCallback(self: *AutocompleteUI, callback: *const fn ([]const u8) void) void {
        self.selection_callback = callback;
    }

    /// Select a suggestion by index
    pub fn selectSuggestion(self: *AutocompleteUI, index: i32) void {
        if (index >= 0 and index < self.suggestions.len) {
            self.selected_index = index;
            suggestion_window.g_ui_state.selected_index = index;
            self.current_suggestion = self.suggestions[@intCast(index)];

            // Update UI to highlight the selected suggestion
            if (self.suggestion_window != null) {
                _ = common.InvalidateRect(self.suggestion_window.?, null, 1);
                _ = common.UpdateWindow(self.suggestion_window.?);
            }

            // Try to apply the new suggestion
            if (!text_completion.tryDirectCompletion(self.current_word, self.current_suggestion.?)) {
                _ = text_completion.trySelectionCompletion(self.current_word, self.current_suggestion.?);
            }
        }
    }

    /// Accept the current suggestion
    pub fn acceptSuggestion(self: *AutocompleteUI) void {
        if (self.is_visible and self.current_suggestion != null and self.selection_callback != null) {
            self.selection_callback.?(self.current_suggestion.?);
            self.hideSuggestions();
        }
    }

    /// Clean up resources
    pub fn deinit(self: *AutocompleteUI) void {
        // Clean up window resources
        if (self.suggestion_window != null) {
            _ = common.DestroyWindow(self.suggestion_window.?);
            self.suggestion_window = null;
        }

        // Unregister window class
        if (self.window_class_atom != 0) {
            _ = common.UnregisterClassA(suggestion_window.SUGGESTION_WINDOW_CLASS, self.instance);
        }
    }
};
