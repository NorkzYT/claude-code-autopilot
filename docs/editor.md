# External Editor (`Ctrl+G`)

Press `Ctrl+G` in Claude Code to open an external editor for prompts.
Codex uses the same editor path when launched with `ccx` (via `.claude/bin/codex-local`).

The kit ships a `claude-editor` wrapper that tries, in order:

1. VS Code on PATH
2. VS Code integrated terminal environment
3. VS Code Remote-SSH server (`~/.vscode-server/`)
4. Cursor
5. `nano` or `vim`

## VS Code on Remote Machines

For VS Code to open from `Ctrl+G` on a remote machine:

1. Connect with VS Code Remote-SSH (or a Tailscale SSH flow that installs VS Code server files)
2. Run Claude in the VS Code integrated terminal
3. Use the same non-root user for VS Code and Claude

If you use a plain SSH terminal, the wrapper falls back to `nano` because VS Code IPC is not available.

## Debug detection

```bash
CLAUDE_EDITOR_DEBUG=1 claude-editor test.txt
```

## Codex note

If Codex shows:

`Cannot open external editor: set $VISUAL or $EDITOR before starting Codex.`

launch Codex with:

```bash
ccx
```

`ccx` sets `EDITOR` and `VISUAL` to `claude-editor` automatically when available.

## VS Code keybinding conflict (`Ctrl+G`)

If `Ctrl+G` opens "Go to Recent Directory" instead of the editor, add this to VS Code `keybindings.json`:

```json
[
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
]
```

## Manual editor override

Set a custom editor in `~/.claude/settings.json`:

```json
{
  "env": {
    "EDITOR": "/path/to/editor --wait",
    "VISUAL": "/path/to/editor --wait"
  }
}
```
