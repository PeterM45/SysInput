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
    /// Average character width as a proportion of font height (for width estimation)
    pub const AVG_CHAR_WIDTH_RATIO = 0.6;
    /// Default popup width (pixels)
    pub const DEFAULT_POPUP_WIDTH = 200;
    /// Default popup height (pixels)
    pub const DEFAULT_POPUP_HEIGHT = 150;
    /// Screen edge padding (pixels)
    pub const SCREEN_EDGE_PADDING = 10;
    /// Base DPI value for scaling calculations
    pub const BASE_DPI = 96.0;
    /// Vertical offset below caret (pixels)
    pub const CARET_VERTICAL_OFFSET = 20;
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

/// Performance configuration
pub const PERFORMANCE = struct {
    /// Position cache lifetime in milliseconds (how long to use cached positions)
    pub const POSITION_CACHE_LIFETIME_MS = 200;
    /// Whether to use caching for suggestions
    pub const USE_SUGGESTION_CACHE = true;
    /// Whether to use caching for positions
    pub const USE_POSITION_CACHE = true;
    /// Maximum number of user words to check for suggestions
    pub const MAX_USER_WORDS_TO_CHECK = 1000;
};

/// Window class specific adjustments
pub const WINDOW_CLASS_ADJUSTMENTS = struct {
    /// Vertical offset adjustment for Edit controls
    pub const EDIT_CONTROL_OFFSET = 5;
    /// Vertical offset adjustment for RichEdit controls
    pub const RICHEDIT_CONTROL_OFFSET = -5;
};
