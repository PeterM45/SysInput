pub const core = struct {
    pub const buffer = @import("core/buffer.zig");
    pub const config = @import("core/config.zig");
    pub const debug = @import("core/debug.zig");
    pub const buffer_controller = @import("core/buffer_controller.zig");
};

pub const input = struct {
    pub const keyboard = @import("input/keyboard.zig");
    pub const text_field = @import("input/text_field.zig");
    pub const window_detection = @import("input/window_detection.zig");
};

pub const suggestion = struct {
    pub const manager = @import("suggestion/manager.zig");
    pub const stats = @import("suggestion/stats.zig");
};

pub const text = struct {
    pub const autocomplete = @import("text/autocomplete.zig");
    pub const dictionary = @import("text/dictionary.zig");
    pub const edit_distance = @import("text/edit_distance.zig");
    pub const spellcheck = @import("text/spellcheck.zig");
    pub const insertion = @import("text/insertion.zig");
};

pub const ui = struct {
    pub const position = @import("ui/position.zig");
    pub const suggestion_ui = @import("ui/suggestion_ui.zig");
    pub const window = @import("ui/window.zig");
};

pub const win32 = struct {
    pub const api = @import("win32/api.zig");
    pub const hook = @import("win32/hook.zig");
    pub const text_inject = @import("win32/text_inject.zig");
};

// Root-level modules
pub const buffer_controller = @import("core/buffer_controller.zig");
