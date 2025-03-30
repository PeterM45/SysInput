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
    /// Line height as multiple of font height
    pub const LINE_HEIGHT_RATIO = 1.25;
    /// Font face name
    pub const FONT_FACE = "Segoe UI\x00";
    /// Animation duration for suggestion popup (ms)
    pub const ANIMATION_DURATION_MS = 150;
    /// Opacity for suggestion window (0-255)
    pub const SUGGESTION_OPACITY = 245;
    /// Suggestion window corner radius
    pub const CORNER_RADIUS = 4;
    /// Z-index for suggestion window (HWND_TOPMOST for always on top)
    pub const Z_INDEX = 0xFFFFFFFF; // HWND_TOPMOST
};

/// Text handling configuration
pub const TEXT = struct {
    /// Maximum buffer size
    pub const MAX_BUFFER_SIZE = 4096;
    /// Maximum suggestion length
    pub const MAX_SUGGESTION_LEN = 256;
    /// Maximum number of suggestions to show
    pub const MAX_SUGGESTIONS = 5;
    /// Maximum word search depth in dictionary
    pub const MAX_WORD_SEARCH_DEPTH = 1000;
    /// Case sensitivity for word comparison (true = case sensitive)
    pub const CASE_SENSITIVE = false;
};

/// Behavior configuration
pub const BEHAVIOR = struct {
    /// Whether to consume Enter key after accepting suggestion
    pub const CONSUME_ENTER_KEY = true;
    /// Minimum word length to trigger suggestions
    pub const MIN_TRIGGER_LEN = 2;
    /// Maximum edit distance for spelling corrections
    pub const MAX_EDIT_DISTANCE = 2;
    /// Whether to automatically show suggestions as you type
    pub const AUTO_SHOW_SUGGESTIONS = true;
    /// Whether to close suggestions when ESC is pressed
    pub const CLOSE_ON_ESC = true;
    /// Whether to insert a space after accepting a suggestion
    pub const INSERT_SPACE_AFTER_COMPLETION = true;
    /// Whether to learn from accepted suggestions
    pub const LEARN_FROM_ACCEPTED = true;
    /// Maximum number of user words to remember
    pub const MAX_USER_WORDS = 10000;
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
    /// Delay between key processing (ms)
    pub const KEY_PROCESSING_DELAY_MS = 5;
    /// Delay after text insertion (ms)
    pub const TEXT_INSERTION_DELAY_MS = 20;
    /// Delay for clipboard operations (ms)
    pub const CLIPBOARD_OPERATION_DELAY_MS = 50;
    /// Maximum retries for text insertion operations
    pub const MAX_INSERTION_RETRIES = 3;
    /// Delay between insertion retries (ms)
    pub const INSERTION_RETRY_DELAY_MS = 30;
};

/// Window class specific adjustments
pub const WINDOW_CLASS_ADJUSTMENTS = struct {
    /// Vertical offset adjustment for Edit controls
    pub const EDIT_CONTROL_OFFSET = 5;
    /// Vertical offset adjustment for RichEdit controls
    pub const RICHEDIT_CONTROL_OFFSET = -5;
    /// Notepad special handling flag
    pub const NOTEPAD_SPECIAL_HANDLING = true;
};

/// Win32 API specific configuration
pub const WIN32 = struct {
    /// Standard window style for suggestion popup
    pub const SUGGESTION_WINDOW_STYLE = 0x80000000; // WS_POPUP
    /// Extended window style for suggestion popup
    pub const SUGGESTION_WINDOW_EX_STYLE = 0x00000008 | 0x00000080 | 0x08000000; // WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE
    /// Window class style for suggestion popup
    pub const SUGGESTION_CLASS_STYLE = 0x00020000; // CS_DROPSHADOW
    /// Clipboard format for text operations
    pub const CLIPBOARD_FORMAT = 1; // CF_TEXT
    /// Global memory allocation flags
    pub const MEMORY_ALLOC_FLAGS = 0x0002; // GMEM_MOVEABLE
    /// Default draw quality for fonts
    pub const FONT_QUALITY = 5; // CLEARTYPE_QUALITY
    /// Font weight
    pub const FONT_WEIGHT_NORMAL = 400; // FW_NORMAL
    /// Font character set
    pub const FONT_CHARSET = 0; // ANSI_CHARSET
};

/// Stats collection configuration
pub const STATS = struct {
    /// Whether to collect usage statistics
    pub const COLLECT_STATS = true;
    /// Interval for saving stats (ms)
    pub const STATS_SAVE_INTERVAL_MS = 60000; // 1 minute
    /// Whether to log detailed stats
    pub const DETAILED_STATS = false;
};

/// Debug configuration
pub const DEBUG = struct {
    /// Whether debug mode is enabled
    pub const DEBUG_MODE = true;
    /// Current debug level (0=Off, 1=Error, 2=Warning, 3=Info, 4=Debug, 5=Trace)
    pub const DEBUG_LEVEL = 4;
    /// Whether to log caret position info
    pub const LOG_CARET_POSITIONS = false;
    /// Whether to log buffer changes
    pub const LOG_BUFFER_CHANGES = false;
    /// Whether to log suggestion generation
    pub const LOG_SUGGESTIONS = true;
    /// Whether to log insertion methods
    pub const LOG_INSERTION_METHODS = true;
};
