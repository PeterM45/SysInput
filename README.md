# SysInput

SysInput is a Windows utility written in Zig that provides system-wide autocomplete and spell checking across all applications. It runs in the background, captures keystrokes via Windows hooks, detects text fields, and shows intelligent suggestions near the text cursor.

## Demo

![SysInput Demo](https://github.com/user-attachments/assets/95c258c5-f25d-4a10-8337-2f7532c056e5)

## Features

- **System-wide text suggestions** - Works in any application with standard text fields
- **Intelligent autocomplete** - Learns from your typing patterns
- **Spell checking** - Identifies and suggests corrections for misspelled words
- **Minimal resource usage** - Written in Zig for efficiency and small footprint
- **Adaptive learning** - Remembers which insertion methods work best for different applications

## Installation

### Prerequisites

- Windows 10 or 11
- [Zig 0.14.0](https://ziglang.org/download/) or later

### Building from Source

1. Clone the repository:

   ```
   git clone https://github.com/PeterM45/SysInput.git
   cd SysInput
   ```

2. Build with Zig:

   ```
   zig build
   ```

3. Run the application:
   ```
   zig build run
   ```

The application will start running in the background. Type in any text field and press Tab to accept suggestions.

## Usage

SysInput works automatically in most text fields:

1. Type at least 2 characters in any text field
2. Suggestions will appear near your cursor
3. Press Tab or Enter to accept the highlighted suggestion
4. Use Up/Down arrows to navigate through suggestions

### Keyboard Shortcuts

| Key        | Action                          |
| ---------- | ------------------------------- |
| Tab        | Accept current suggestion       |
| Enter      | Accept current suggestion       |
| Down Arrow | Navigate to next suggestion     |
| Up Arrow   | Navigate to previous suggestion |
| Esc        | Exit SysInput                   |

## Project Architecture

SysInput is organized into several modules:

- **Core:** Text buffer implementation, configuration, and debugging utilities
- **Input:** Keyboard hooks and text field detection
- **Text:** Autocomplete engine, dictionary management, spell checking, and text insertion
- **UI:** Suggestion UI, positioning, and window management
- **Win32:** Windows API bindings and hook implementations

### Key Components

- **Keyboard Hook System:** Captures keystrokes system-wide using Windows hooks
- **Text Field Detection:** Identifies active text fields across applications
- **Buffer Management:** Maintains synchronized text content for processing
- **Suggestion Engine:** Generates completions based on dictionary and user patterns
- **Text Insertion:** Multiple strategies for reliable text insertion across different applications
- **UI System:** Lightweight overlay windows for displaying suggestions

## Project Structure

```
SysInput/
├── build.zig             - Build configuration
├── resources/
│   └── dictionary.txt    - Word dictionary for suggestions
└── src/
    ├── buffer_controller.zig - Text buffer management
    ├── core/               - Core functionality
    │   ├── buffer.zig      - Text buffer implementation
    │   ├── config.zig      - Configuration
    │   └── debug.zig       - Debugging utilities
    ├── input/             - Input handling
    │   ├── keyboard.zig    - Keyboard hook and processing
    │   ├── text_field.zig  - Text field detection
    │   └── window_detection.zig  - Window detection
    ├── main.zig           - Application entry point
    ├── suggestion/        - Suggestion handling
    │   ├── manager.zig     - Suggestion manager
    │   └── stats.zig       - Statistics tracking
    ├── sysinput.zig       - Main module imports
    ├── text/              - Text processing
    │   ├── autocomplete.zig - Autocomplete engine
    │   ├── dictionary.zig   - Dictionary loading/management
    │   ├── edit_distance.zig - Text similarity algorithms
    │   ├── insertion.zig     - Text insertion methods
    │   └── spellcheck.zig    - Spell checking
    ├── ui/                - User interface
    │   ├── position.zig    - UI positioning logic
    │   ├── suggestion_ui.zig - Suggestion UI
    │   └── window.zig      - Window management
    └── win32/             - Windows API bindings
        ├── api.zig         - Windows API definitions
        ├── hook.zig        - Hook implementation
        └── text_inject.zig - Text injection utilities
```

## Text Insertion Methods

SysInput uses multiple strategies to insert text reliably across different applications:

1. **Clipboard Insertion:** Uses clipboard operations to replace text
2. **Key Simulation:** Simulates keyboard input character by character
3. **Direct Message Posting:** Sends Windows messages directly to applications
4. **Application-Specific Methods:** Specialized approaches for specific applications

The system automatically learns which method works best with each application class for optimal reliability.

## Contributing

Contributions are welcome! Here's how you can help:

### Getting Started

1. Fork the repository
2. Clone your fork
3. Create a branch for your changes
4. Make your changes
5. Submit a pull request

### Coding Style

- Use Zig's native style with 4 spaces for indentation
- Follow Zig's naming conventions
- Add meaningful comments, especially for complex algorithms
- Include error handling for all operations that may fail

### Areas That Need Help

- Expanded application compatibility
- Performance optimizations
- Suggestion popup location improvements
- Multi-monitor support
- Customization options
- Internationalization/multi-language support

## Troubleshooting

### Suggestions Not Appearing

- Ensure SysInput is running
- Try typing in a different application
- Make sure you've typed at least 2 characters
- Check if the text field is a standard Windows control

### Text Insertion Issues

- Try a different insertion method
- Some applications with security restrictions may limit text automation
- Custom controls in specialized applications may not be fully compatible

## Acknowledgments

- Thanks to the Zig community for their excellent language and tools
- Inspired by autocomplete features from various text editors and IDEs

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
