const std = @import("std");
const sysinput = @import("root").sysinput;

const api = sysinput.win32.api;
const debug = sysinput.core.debug;
const config = sysinput.core.config;

/// Window class for suggestion popup
pub const SUGGESTION_WINDOW_CLASS = "SysInputSuggestions";

/// Suggestion window margins
pub const WINDOW_PADDING = 2;

/// UI state structure (used as window userData)
pub const UiState = struct {
    suggestions: [][]const u8,
    selected_index: i32,
    font: ?api.HFONT,
};

/// Global UI state (since Windows callbacks need global access)
pub var g_ui_state = UiState{
    .suggestions = &[_][]const u8{},
    .selected_index = -1,
    .font = null,
};

/// Window procedure for suggestion window
pub fn suggestionWindowProc(
    hwnd: api.HWND,
    msg: api.UINT,
    wParam: api.WPARAM,
    lParam: api.LPARAM,
) callconv(.C) api.LRESULT {
    switch (msg) {
        api.WM_CREATE => {
            debug.debugPrint("Suggestion window created\n", .{});

            // Create a font for the suggestions - using Segoe UI for modern look
            g_ui_state.font = api.CreateFontA(
                config.UI.SUGGESTION_FONT_HEIGHT, // height
                0, // width (0 = auto)
                0, // escapement
                0, // orientation
                config.WIN32.FONT_WEIGHT_NORMAL, // weight
                0, // italic
                0, // underline
                0, // strikeout
                config.WIN32.FONT_CHARSET, // charset
                api.OUT_DEFAULT_PRECIS, // output precision
                api.CLIP_DEFAULT_PRECIS, // clipping precision
                config.WIN32.FONT_QUALITY, // quality
                api.DEFAULT_PITCH | api.FF_DONTCARE, // pitch and family
                config.UI.FONT_FACE, // face name
            );

            if (g_ui_state.font == null) {
                debug.debugPrint("Failed to create font\n", .{});
            }

            return 0;
        },

        api.WM_PAINT => {
            var ps: api.PAINTSTRUCT = undefined;
            const hdc = api.BeginPaint(hwnd, &ps);
            defer _ = api.EndPaint(hwnd, &ps);

            debug.debugPrint("Drawing {d} suggestions\n", .{g_ui_state.suggestions.len});

            // Draw suggestions
            if (g_ui_state.suggestions.len > 0) {
                var client_rect: api.RECT = undefined;
                _ = api.GetClientRect(hwnd, &client_rect);

                // Set font
                if (g_ui_state.font) |font| {
                    _ = api.SelectObject(hdc, font);
                }

                // Set text settings for better appearance
                _ = api.SetBkMode(hdc, api.TRANSPARENT);
                _ = api.SetTextColor(hdc, config.UI.TEXT_COLOR);

                // Draw each suggestion
                var i: usize = 0;
                var y: i32 = WINDOW_PADDING;
                const line_height = config.UI.SUGGESTION_FONT_HEIGHT +
                    @as(i32, @intFromFloat(@as(f32, @floatFromInt(config.UI.SUGGESTION_FONT_HEIGHT)) * (config.UI.LINE_HEIGHT_RATIO - 1.0)));

                while (i < g_ui_state.suggestions.len) : (i += 1) {
                    const is_selected = g_ui_state.selected_index == @as(i32, @intCast(i));
                    const suggestion = g_ui_state.suggestions[i];

                    // Set rect for this suggestion
                    var rect = api.RECT{
                        .left = WINDOW_PADDING,
                        .top = y,
                        .right = client_rect.right - WINDOW_PADDING,
                        .bottom = y + line_height,
                    };

                    // Draw background for selection (simplified to avoid errors)
                    if (is_selected) {
                        const brush = api.CreateSolidBrush(config.UI.SELECTED_BG_COLOR);
                        if (brush != null) {
                            defer _ = api.DeleteObject(brush.?);
                            _ = api.FillRect(hdc, &rect, brush.?);

                            // Use selected text color
                            _ = api.SetTextColor(hdc, config.UI.SELECTED_TEXT_COLOR);
                        }
                    } else {
                        _ = api.SetTextColor(hdc, config.UI.TEXT_COLOR);
                    }

                    // Draw suggestion text
                    var buffer: [config.TEXT.MAX_SUGGESTION_LEN:0]u8 = undefined;
                    std.mem.copyForwards(u8, &buffer, suggestion);
                    buffer[suggestion.len] = 0; // Null terminate

                    // Add padding for text
                    rect.left += 8;
                    _ = api.DrawTextA(hdc, &buffer, @intCast(suggestion.len), &rect, api.DT_LEFT | api.DT_SINGLELINE | api.DT_VCENTER);

                    y += line_height;
                }
            }

            return 0;
        },

        api.WM_LBUTTONDOWN => {
            // Get coordinates
            const x_pos = @as(i16, @truncate(lParam & 0xFFFF));
            const y = @as(i16, @truncate((lParam >> 16) & 0xFFFF));
            _ = x_pos; // Use the x_pos to avoid unused variable warning

            // Calculate which suggestion was clicked
            const line_height = config.UI.SUGGESTION_FONT_HEIGHT +
                @as(i32, @intFromFloat(@as(f32, @floatFromInt(config.UI.SUGGESTION_FONT_HEIGHT)) * (config.UI.LINE_HEIGHT_RATIO - 1.0)));

            const index = @divTrunc(y - WINDOW_PADDING, line_height);

            if (index >= 0 and index < g_ui_state.suggestions.len) {
                // Update selected index
                g_ui_state.selected_index = @intCast(index);

                // Redraw
                _ = api.InvalidateRect(hwnd, null, 1);

                // Send a message to parent about selection
                const parent = api.GetParent(hwnd);
                if (parent != null) {
                    _ = api.PostMessageA(parent.?, api.WM_USER + 1, @intCast(index), 0);
                }
            }

            return 0;
        },

        api.WM_ERASEBKGND => {
            const hdc = @as(api.HDC, @ptrFromInt(wParam));

            var rect: api.RECT = undefined;
            _ = api.GetClientRect(hwnd, &rect);

            const brush = api.CreateSolidBrush(config.UI.BG_COLOR);
            if (brush != null) {
                defer _ = api.DeleteObject(brush.?);
                _ = api.FillRect(hdc, &rect, brush.?);
            }
            return 1; // We handled it
        },

        api.WM_DESTROY => {
            if (g_ui_state.font) |font| {
                _ = api.DeleteObject(font);
                g_ui_state.font = null;
            }
            return 0;
        },

        else => return api.DefWindowProcA(hwnd, msg, wParam, lParam),
    }
}

/// Register the suggestion window class
pub fn registerSuggestionWindowClass(instance: api.HINSTANCE) !api.ATOM {
    const wc = api.WNDCLASSEX{
        .cbSize = @sizeOf(api.WNDCLASSEX),
        .style = config.WIN32.SUGGESTION_CLASS_STYLE, // Use config value
        .lpfnWndProc = suggestionWindowProc,
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .hInstance = instance,
        .hIcon = null,
        .hCursor = api.LoadCursorA(null, api.makeIntResource(api.IDC_ARROW)),
        .hbrBackground = @as(*anyopaque, @ptrCast(api.GetStockObject(api.WHITE_BRUSH).?)),
        .lpszMenuName = null,
        .lpszClassName = SUGGESTION_WINDOW_CLASS,
        .hIconSm = null,
    };

    const atom = api.RegisterClassExA(&wc);
    if (atom == 0) {
        debug.debugPrint("Failed to register window class\n", .{});
        return error.WindowClassRegistrationFailed;
    }

    return atom;
}
