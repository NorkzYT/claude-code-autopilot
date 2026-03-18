# External Editor (Ctrl+G)

## Overview

Claude Code supports opening files in your preferred external editor using **Ctrl+G**.

The `claude-editor` wrapper automatically detects and uses your available editors in this priority order:

1. **VS Code** (local install)
2. **VS Code Remote-SSH** (per-user `~/.vscode-server`)
3. **Cursor** (VS Code fork)
4. **Fallback**: nano/vim if no GUI editor found

## Usage

### In Claude Code
Press **Ctrl+G** while viewing a file to open it in your external editor.

### In Codex
Launch with `ccx` to automatically set `EDITOR`/`VISUAL` environment variables.

## VS Code Keybinding Conflict Fix

If Ctrl+G opens the directory picker instead of the external editor, add this to your VS Code `keybindings.json`:

```json
{
  "key": "ctrl+g",
  "command": "-workbench.action.terminal.goToRecentDirectory",
  "when": "terminalFocus"
},
{
  "key": "ctrl+shift+alt+p",
  "command": "workbench.action.terminal.goToRecentDirectory",
  "when": "terminalFocus"
}
```

**Alternative**: Use `"key": "escape"` to disable the directory picker completely.

## Editor Detection

The wrapper checks for editors in this order:

1. `code` (VS Code CLI)
2. `~/.vscode-server/bin/*/bin/code` (VS Code Remote-SSH)
3. `cursor` (Cursor editor)
4. `nano`, `vim`, `vi` (terminal fallback)

## Troubleshooting

### Editor not opening?
1. Check if VS Code CLI is installed: `code --version`
2. Install VS Code CLI: Open VS Code → Command Palette (Ctrl+Shift+P) → "Shell Command: Install 'code' command in PATH"
3. For Remote-SSH: Ensure VS Code server is installed on the remote machine

### Wrong editor opens?
Set your preferred editor explicitly:
```bash
export EDITOR="code --wait"
export VISUAL="code --wait"
```

Add to your `~/.bashrc` or `~/.zshrc` to make it permanent.
