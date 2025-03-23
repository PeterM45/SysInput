const std = @import("std");
const common = @import("../win32/common.zig");

/// Window class for suggestion popup
pub const SUGGESTION_WINDOW_CLASS = "SysInputSuggestions";
pub const MAX_SUGGESTION_LEN = 256;

/// Font used for suggestions
pub const SUGGESTION_FONT_HEIGHT = 16;

/// Background color
pub const BG_COLOR = 0x00FFFFFF; // White
pub const SELECTED_BG_COLOR = 0x00B3D9FF; // Light blue
pub const TEXT_COLOR = 0x00000000; // Black

/// Suggestion window margins
pub const WINDOW_PADDING = 2;

/// UI state structure (used as window userData)
pub const UiState = struct {
    suggestions: [][]const u8,
    selected_index: i32,
    font: ?common.HFONT,
};

/// Global UI state (since Windows callbacks need global access)
pub var g_ui_state = UiState{
    .suggestions = &[_][]const u8{},
    .selected_index = -1,
    .font = null,
};

/// Window procedure for suggestion window
pub fn suggestionWindowProc(
    hwnd: common.HWND,
    msg: common.UINT,
    wParam: common.WPARAM,
    lParam: common.LPARAM,
) callconv(.C) common.LRESULT {
    switch (msg) {
        common.WM_CREATE => {
            std.debug.print("Suggestion window created\n", .{});

            // Create a font for the suggestions
            g_ui_state.font = common.CreateFontA(
                SUGGESTION_FONT_HEIGHT, // height
                0, // width (0 = auto)
                0, // escapement
                0, // orientation
                common.FW_NORMAL, // weight
                0, // italic
                0, // underline
                0, // strikeout
                common.ANSI_CHARSET, // charset
                common.OUT_DEFAULT_PRECIS, // output precision
                common.CLIP_DEFAULT_PRECIS, // clipping precision
                common.DEFAULT_QUALITY, // quality
                common.DEFAULT_PITCH | common.FF_DONTCARE, // pitch and family
                "Segoe UI\x00", // face name (null-terminated)
            );

            if (g_ui_state.font == null) {
                std.debug.print("Failed to create font\n", .{});
            }

            return 0;
        },

        common.WM_PAINT => {
            var ps: common.PAINTSTRUCT = undefined;
            const hdc = common.BeginPaint(hwnd, &ps);
            defer _ = common.EndPaint(hwnd, &ps);

            // Draw suggestions
            if (g_ui_state.suggestions.len > 0) {
                var client_rect: common.RECT = undefined;
                _ = common.GetClientRect(hwnd, &client_rect);

                // Set font
                if (g_ui_state.font) |font| {
                    _ = common.SelectObject(hdc, font);
                }

                // Clear background
                _ = common.SetBkMode(hdc, common.TRANSPARENT);

                // Draw each suggestion
                var i: usize = 0;
                var y: i32 = WINDOW_PADDING;
                const line_height = SUGGESTION_FONT_HEIGHT + 4; // Add some padding

                while (i < g_ui_state.suggestions.len) : (i += 1) {
                    const is_selected = g_ui_state.selected_index == @as(i32, @intCast(i));
                    const suggestion = g_ui_state.suggestions[i];

                    // Set rect for this suggestion
                    var rect = common.RECT{
                        .left = WINDOW_PADDING,
                        .top = y,
                        .right = client_rect.right - WINDOW_PADDING,
                        .bottom = y + line_height,
                    };

                    // Draw background for selection
                    if (is_selected) {
                        const brush = common.CreateSolidBrush(SELECTED_BG_COLOR);
                        if (brush != null) {
                            defer _ = common.DeleteObject(brush.?);
                            _ = common.FillRect(hdc, &rect, brush.?);
                        }
                    }

                    // Draw suggestion text
                    _ = common.SetTextColor(hdc, TEXT_COLOR);

                    // Convert to wchar if needed or use multibyte version
                    var buffer: [MAX_SUGGESTION_LEN:0]u8 = undefined;
                    std.mem.copyForwards(u8, &buffer, suggestion);
                    buffer[suggestion.len] = 0; // Null terminate

                    _ = common.DrawTextA(hdc, &buffer, @intCast(suggestion.len), &rect, common.DT_LEFT | common.DT_SINGLELINE | common.DT_VCENTER);

                    y += line_height;
                }
            }

            return 0;
        },

        common.WM_LBUTTONDOWN => {
            // Get coordinates
            const x_pos = @as(i16, @truncate(lParam & 0xFFFF));
            const y = @as(i16, @truncate((lParam >> 16) & 0xFFFF));
            _ = x_pos; // Use the x_pos to avoid unused variable warning

            // Calculate which suggestion was clicked
            const line_height = SUGGESTION_FONT_HEIGHT + 4;
            const index = @divTrunc(y - WINDOW_PADDING, line_height);

            if (index >= 0 and index < g_ui_state.suggestions.len) {
                // Update selected index
                g_ui_state.selected_index = @intCast(index);

                // Redraw
                _ = common.InvalidateRect(hwnd, null, 1);

                // Send a message to parent about selection
                const parent = common.GetParent(hwnd);
                if (parent != null) {
                    _ = common.PostMessageA(parent.?, common.WM_USER + 1, @intCast(index), 0);
                }
            }

            return 0;
        },

        common.WM_ERASEBKGND => {
            const hdc = @as(common.HDC, @ptrFromInt(wParam));

            var rect: common.RECT = undefined;
            _ = common.GetClientRect(hwnd, &rect);

            const brush = common.CreateSolidBrush(BG_COLOR);
            if (brush != null) {
                defer _ = common.DeleteObject(brush.?);
                _ = common.FillRect(hdc, &rect, brush.?);
            }
            return 1; // We handled it
        },

        common.WM_DESTROY => {
            if (g_ui_state.font) |font| {
                _ = common.DeleteObject(font);
                g_ui_state.font = null;
            }
            return 0;
        },

        else => return common.DefWindowProcA(hwnd, msg, wParam, lParam),
    }
}

/// Register the suggestion window class
pub fn registerSuggestionWindowClass(instance: common.HINSTANCE) !common.ATOM {
    const wc = common.WNDCLASSEX{
        .cbSize = @sizeOf(common.WNDCLASSEX),
        .style = common.CS_DROPSHADOW,
        .lpfnWndProc = suggestionWindowProc,
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .hInstance = instance,
        .hIcon = null,
        .hCursor = common.LoadCursorA(null, common.makeIntResource(common.IDC_ARROW)),
        .hbrBackground = @as(*anyopaque, @ptrCast(common.GetStockObject(common.WHITE_BRUSH).?)), // Use stock white brush
        .lpszMenuName = null,
        .lpszClassName = SUGGESTION_WINDOW_CLASS,
        .hIconSm = null,
    };

    const atom = common.RegisterClassExA(&wc);
    if (atom == 0) {
        std.debug.print("Failed to register window class\n", .{});
        return error.WindowClassRegistrationFailed;
    }

    return atom;
}
