# SysInput

SysInput is a lightweight system utility written in Zig that provides spellchecking and autocompletion capabilities across Windows applications. It attempts to offer these features at a system level, rather than being limited to a single application.

## Features

- 📝 **Text buffer management**: Tracks what you're typing across applications
- 🔍 **Text field detection**: Identifies active text input fields
- ✅ **Spellchecking**: Detects misspelled words as you type
- 🔮 **Autocompletion**: Suggests words as you type based on a dictionary
- ⌨️ **Keyboard navigation**: Navigate through suggestions using arrow keys

## How It Works

SysInput uses Windows API hooks to:

1. Install a low-level keyboard hook to capture keystrokes
2. Maintain a text buffer that mirrors what you're typing
3. Detect active text fields across applications
4. Provide inline word suggestions based on what you're typing
5. Allow keyboard navigation through suggestions

## Building from Source

### Prerequisites

- Zig 0.14.0 or newer
- Windows operating system
- A dictionary file (placed in `resources/dictionary.txt`)

### Build Commands

```bash
# Clone the repository
git clone https://github.com/yourusername/SysInput.git
cd SysInput

# Build the executable
zig build-exe src/main.zig -luser32 -lgdi32 -fsingle-threaded
```

## Usage

1. Run the executable
2. Start typing in any text field in any application
3. As you type, SysInput will:
   - Check spelling against its dictionary
   - Offer word suggestions as you type
   - Show suggestion overlays near your cursor

### Keyboard Shortcuts

- `Tab` / `Right Arrow` / `Enter`: Accept the current suggestion
- `Up Arrow`: Move to previous suggestion
- `Down Arrow`: Move to next suggestion
- `ESC`: Exit SysInput

## Project Structure

```
├───src
│   ├───buffer           # Text buffer management
│   ├───detection        # Text field detection
│   ├───spellcheck       # Spellchecking functionality
│   ├───autocomplete     # Word suggestion engine
│   ├───ui               # User interface for suggestions
│   ├───win32            # Windows API integration
│   └───main.zig         # Application entry point
├───resources
│   └───dictionary.txt   # Dictionary for spellchecking/autocompletion
```

## Current Limitations

- Works best with standard Windows text controls (e.g., Notepad, text fields)
- May not integrate with applications using custom text rendering
- Dictionary is static and not context-aware
- Inline completion functionality may not work in all applications
- Limited to the English language by default

## Future Development

- Improve text field detection for better application compatibility
- Add support for custom dictionaries and multiple languages
- Create a more robust suggestion engine with context awareness
- Implement learning from user typing patterns
- Add a UI for configuration and dictionary management
- Support for custom styling of suggestion interface

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgments

- Built with Zig programming language
- Uses Windows API for system-level integration
