/// UI configuration
pub const UI = struct {
    /// Font height for suggestion window
    pub const SUGGESTION_FONT_HEIGHT = 16;
    /// Window padding
    pub const WINDOW_PADDING = 4;
    /// Background color (white)
    pub const BG_COLOR = 0x00FAFAFA;
    /// Selected item background color (light blue)
    pub const SELECTED_BG_COLOR = 0x002B5DFC;
    /// Text color (black)
    pub const TEXT_COLOR = 0x00303030;
    /// Selected item text color (white)
    pub const SELECTED_TEXT_COLOR = 0x00FFFFFF;
};

/// Text handling configuration
pub const TEXT = struct {
    /// Maximum buffer size
    pub const MAX_BUFFER_SIZE = 4096;
    /// Maximum suggestion length
    pub const MAX_SUGGESTION_LEN = 256;
    /// Maximum number of suggestions to show
    pub const MAX_SUGGESTIONS = 5;
};

/// Behavior configuration
pub const BEHAVIOR = struct {
    /// Whether to consume Enter key after accepting suggestion
    pub const CONSUME_ENTER_KEY = true;
    /// Minimum word length to trigger suggestions
    pub const MIN_TRIGGER_LEN = 2;
    /// Maximum edit distance for spelling corrections
    pub const MAX_EDIT_DISTANCE = 2;
};
