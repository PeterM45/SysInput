const std = @import("std");
const sysinput = @import("../sysinput.zig");

const api = sysinput.win32.api;
const window = sysinput.ui.window;
const text_inject = sysinput.win32.text_inject;
const position = sysinput.ui.position;
const debug = sysinput.core.debug;

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
    suggestion_window: ?api.HWND,
    /// Module instance
    instance: api.HINSTANCE,
    /// Window class atom for suggestion window
    window_class_atom: api.ATOM,

    /// Initialize the inline completion
    pub fn init(allocator: std.mem.Allocator, instance: api.HINSTANCE) !AutocompleteUI {
        // Register window class for suggestions
        const atom = try window.registerSuggestionWindowClass(instance);

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
        debug.debugPrint("UI showSuggestions called with {d} suggestions\n", .{suggestions.len});

        self.suggestions = suggestions;
        self.selected_index = 0;
        window.g_ui_state.suggestions = suggestions;
        window.g_ui_state.selected_index = 0;

        // If we have suggestions, mark as visible and try to apply the first one
        if (suggestions.len > 0) {
            self.is_visible = true;
            self.current_suggestion = suggestions[0];
            debug.debugPrint("First suggestion: '{s}'\n", .{self.current_suggestion.?});

            // Try multiple approaches for inline completion
            if (!text_inject.tryDirectCompletion(self.current_word, self.current_suggestion.?)) {
                // If direct completion fails, try using selection-based approach
                _ = text_inject.trySelectionCompletion(self.current_word, self.current_suggestion.?);
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
        var suggested_pos = api.POINT{ .x = x, .y = y };

        // Only use provided coordinates if they're non-zero
        if (x == 0 and y == 0) {
            // Get intelligent position based on caret or text field
            suggested_pos = position.getCaretPosition();
        }

        // Get DPI scaling to adjust positioning and sizes
        const hdc = api.GetDC(null);
        const dpi = if (hdc != null) @as(f32, @floatFromInt(api.GetDeviceCaps(hdc.?, api.LOGPIXELSY))) / 96.0 else 1.0;
        if (hdc != null) {
            _ = api.ReleaseDC(null, hdc.?);
        }

        // Add DPI-aware padding below the caret
        suggested_pos.y += @intFromFloat(@as(f32, 20.0 * dpi));

        // Calculate window size based on suggestions
        const size = position.calculateSuggestionWindowSize(self.suggestions, window.SUGGESTION_FONT_HEIGHT, window.WINDOW_PADDING);

        // Adjust for screen boundaries
        const screen_width = api.GetSystemMetrics(api.SM_CXSCREEN);
        const screen_height = api.GetSystemMetrics(api.SM_CYSCREEN);

        if (suggested_pos.x + size.width > screen_width) {
            suggested_pos.x = screen_width - size.width;
        }
        if (suggested_pos.y + size.height > screen_height) {
            // Move above caret if not enough space below
            const height_f32: f32 = @floatFromInt(size.height);
            suggested_pos.y -= @intFromFloat((20.0 + height_f32) * dpi);
        }

        debug.debugPrint("Showing suggestion UI at {}, {}\n", .{ suggested_pos.x, suggested_pos.y });

        // Create window if it doesn't exist
        if (self.suggestion_window == null) {
            debug.debugPrint("Creating suggestion window\n", .{});

            const new_window = api.CreateWindowExA(
                api.WS_EX_TOPMOST | api.WS_EX_TOOLWINDOW | api.WS_EX_NOACTIVATE,
                window.SUGGESTION_WINDOW_CLASS,
                "Suggestions\x00",
                api.WS_POPUP | api.WS_BORDER,
                suggested_pos.x,
                suggested_pos.y,
                size.width,
                size.height,
                null, // No parent
                null, // No menu
                self.instance,
                null, // No lpParam
            );

            if (new_window == null) {
                debug.debugPrint("Failed to create suggestion window\n", .{});
                return error.WindowCreationFailed;
            }

            self.suggestion_window = new_window;
        } else {
            // Reposition existing window
            _ = api.SetWindowPos(
                self.suggestion_window.?,
                api.HWND_TOPMOST,
                suggested_pos.x,
                suggested_pos.y,
                size.width,
                size.height,
                api.SWP_SHOWWINDOW,
            );
        }

        // Show the window
        _ = api.ShowWindow(self.suggestion_window.?, api.SW_SHOWNOACTIVATE);
        _ = api.UpdateWindow(self.suggestion_window.?);
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
            _ = api.ShowWindow(self.suggestion_window.?, api.SW_HIDE);
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
            window.g_ui_state.selected_index = index;
            self.current_suggestion = self.suggestions[@intCast(index)];

            // Update UI to highlight the selected suggestion
            if (self.suggestion_window != null) {
                _ = api.InvalidateRect(self.suggestion_window.?, null, 1);
                _ = api.UpdateWindow(self.suggestion_window.?);
            }

            // Try to apply the new suggestion
            if (!text_inject.tryDirectCompletion(self.current_word, self.current_suggestion.?)) {
                _ = text_inject.trySelectionCompletion(self.current_word, self.current_suggestion.?);
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
            _ = api.DestroyWindow(self.suggestion_window.?);
            self.suggestion_window = null;
        }

        // Unregister window class
        if (self.window_class_atom != 0) {
            _ = api.UnregisterClassA(window.SUGGESTION_WINDOW_CLASS, self.instance);
        }
    }
};
