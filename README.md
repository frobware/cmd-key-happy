# macOS Command/Option Key Mapper (for Linux refugees)

A utility that makes your macOS keyboard work like a Linux keyboard by swapping modifier keys, in the applications you name and nowhere else:
- The physical Option (⌥) key functions as Command (⌘)
- The physical Command (⌘) key functions as Option/Alt (⌥)

Anything you do not list is left alone, so your terminal gets the
Linux behaviour whilst the rest of the system keeps the macOS one.
See [Configuration](#configuration) for the list.

## Why Use This?

On Linux, the Alt key (next to spacebar) is used for terminal shortcuts like alt-backspace and alt-f. This utility places that same functionality on the same physical key on your Mac keyboard, making muscle memory work across both systems.

## Common Use Cases

- Terminal navigation (alt-f, alt-b, alt-backspace)
- Emacs in terminal mode (`emacs -nw`)
- Any command-line tool that uses readline

## Installation

See [INSTALL.md](INSTALL.md). Settle your code-signing identity before
the first install: the Accessibility grant is keyed on it, and changing
it afterwards means uninstalling first. In short:

```shell
make reload
```

then grant Accessibility to `CmdKeyHappy.app` under System Settings >
Privacy & Security > Accessibility.

## Your terminal must treat Option as Meta

Swapping the modifiers is only half of it. Your terminal also has to
send Option as Meta rather than composing a character, and on macOS
the default is to compose.

Without it, pressing Command-X gives you `≈` -- the macOS Option+X
character -- instead of the `alt-x` your shell or Emacs is waiting
for. That is not cmd-key-happy going wrong: the swap worked, and the
terminal then composed.

| Terminal | Setting | Default |
|---|---|---|
| Ghostty | `macos-option-as-alt = true` | unset |
| kitty | `macos_option_as_alt both` | `no` |
| Alacritty | `option_as_alt = "Both"` under `[window]` | `None` |
| WezTerm | `send_composed_key_when_left_alt_is_pressed = false` and the `right` equivalent | left `false`, right `true` |

Ghostty, kitty and Alacritty also accept `left` or `right` if you want
only one of the two keys treated as Meta.

The cost is that you lose macOS Option+key Unicode input in that
terminal. If you type characters like `≈` or `∆` deliberately, set
this for one Option key only and compose with the other.

## Configuration

The configuration file is located at: `~/Library/Application Support/com.frobware.cmd-key-happy/config`.

This file and its directory are created automatically the first time cmd-key-happy runs.

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

The application name must match the name as it appears in the system's application list.
