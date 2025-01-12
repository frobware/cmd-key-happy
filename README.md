# macOS Command/Option Key Mapper (for Linux refugees)

A utility that makes your macOS keyboard work like a Linux keyboard by swapping modifier keys:
- The physical Option (⌥) key functions as Command (⌘)
- The physical Command (⌘) key functions as Option/Alt (⌥)

## Why Use This?

On Linux, the Alt key (next to spacebar) is used for terminal shortcuts like alt-backspace and alt-f. This utility places that same functionality on the same physical key on your Mac keyboard, making muscle memory work across both systems.

## Common Use Cases

- Terminal navigation (alt-f, alt-b, alt-backspace)
- Emacs in terminal mode (`emacs -nw`)
- Any command-line tool that uses readline

## Installation

[Instructions coming soon]

## Configuration

The configuration file is located at: `~/Library/Application Support/com.frobware.cmd-key-happy/config`.

(TODO) This file is created automatically when you run cmd-key-happy for the first time, along with the necessary directory structure.

The configuration file is line-oriented. Each line specifies the name of an application for which the modifiers option and commands will be swapped for all input. For example:

```plaintext
Alacritty
Ghostty
kitty
```

Explanation:

- Alacritty: The utility will swap command and option keys when using the Alacritty terminal.
- Ghostty: The same behaviour applies to this application.
- kitty: Likewise, the keys are swapped for kitty.

The application name must match the name as it appears in the system’s application list.
