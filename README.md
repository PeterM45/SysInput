# SysInput

## Project Overview

SysInput is a Windows utility written in Zig that provides system-wide autocomplete and spell checking functionality across all applications. It works by capturing keyboard input, detecting text fields, and offering intelligent suggestions as you type.

## Features

- System-wide text autocomplete for all Windows applications
- Real-time spell checking with corrections
- Smart suggestion display near the text cursor
- Application-specific optimizations for better compatibility
- Low-latency operation with minimal system resource usage
- Learns from your typing patterns to improve suggestions over time

## Installation

### Prerequisites

- Windows 10/11
- [Zig 0.14.0](https://ziglang.org/download/) or newer

### Building from Source

1. Clone the repository

```
git clone https://github.com/PeterM45/SysInput.git
cd SysInput
```

2. Build the project

```
zig build
```

3. Run the executable

```
zig build run
```

## Usage

Once SysInput is running, it operates in the background and automatically detects text fields in any application.

### Basic Operation

- Type normally in any application
- SysInput will display suggestions as you type
- Press **Tab**, **Enter**, or **Right Arrow** to accept the current suggestion
- Use **Up/Down Arrow** keys to navigate through multiple suggestions
- Press **Esc** to dismiss suggestions

### Keyboard Shortcuts

- **Alt+Esc**: Exit SysInput
- **Ctrl+Space**: Force suggestion display

## Development Status

SysInput is currently in active development. Key features are implemented, but some aspects are still being refined:

- **Working**: Core autocomplete functionality, suggestion display, and basic word replacement
- **In Progress**: Improved text synchronization with various types of applications
- **Planned**: Configuration UI, custom dictionary support, and additional language support

## Technical Details

### Architecture

SysInput uses a modular design with components for:

- Input handling (keyboard hooks and text field detection)
- Text processing (autocomplete engine and spell checking)
- UI components (suggestion display)
- Win32 API integration (Windows system interaction)

### Building Blocks

- Text buffer management using gap buffer algorithm
- Low-level keyboard event interception via Windows hooks
- Application-aware text insertion techniques
- Adaptive learning from user typing patterns

## Contributing

Contributions are welcome! If you'd like to help improve SysInput:

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Commit your changes: `git commit -am 'Add some amazing feature'`
4. Push to the branch: `git push origin feature/amazing-feature`
5. Submit a pull request

## Acknowledgments

- Built with [Zig](https://ziglang.org/), a general-purpose programming language designed for robustness, optimality, and maintainability.
- Thanks to all contributors who have helped make this project better.
