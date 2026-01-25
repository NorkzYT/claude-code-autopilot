# Claude Code Autopilot Kit

A portable `.claude/` bundle that supercharges Claude Code with **automatic task execution**, **safety guardrails**, and **session persistence**.

Once installed, Claude automatically launches the **autopilot agent** for substantive tasks — no manual invocation needed.

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/NorkzYT/claude-code-autopilot/main/install.sh \
  | bash -s -- --repo NorkzYT/claude-code-autopilot --ref main --force --bootstrap-linux
```

After install, you'll see your **ntfy.sh subscription URL** — subscribe to get notified when Claude needs your attention.

Then restart Claude Code to load the new configuration.

---

## How It Works

After installation, the kit automatically:

1. **Injects autopilot** — A hook detects substantive prompts and triggers the autopilot agent
2. **Guards dangerous operations** — Blocks `rm -rf`, `sudo`, `curl|bash`, auto-commits, etc.
3. **Protects sensitive files** — Blocks edits to `.env`, secrets, certs, prod configs
4. **Auto-formats code** — Runs Prettier/Black on edited files when configured
5. **Logs everything** — Prompts, commands, and responses go to `.claude/logs/`

---

## Usage Guide

### Just Ask Naturally

For most tasks, simply describe what you want:

```
Add a logout button to the navbar that clears the session and redirects to /login
```

The autopilot agent automatically:
- Explores the codebase to understand the structure
- Plans the implementation
- Makes the changes
- Verifies the result
- Reviews for issues

### Structured Prompts (For Complex Tasks)

For complex or multi-step tasks, use this structure for best results:

```
1) GOAL
- Add user authentication with JWT tokens

2) DEFINITION OF DONE
- [ ] Login endpoint returns JWT on valid credentials
- [ ] Protected routes reject requests without valid token
- [ ] Tests pass

3) CONTEXT
- Using Express.js backend in /src/api
- User model already exists at /src/models/user.js

4) DETAILS
- Use bcrypt for password hashing
- Token expiry: 24 hours
```

### Skip Autopilot for Simple Questions

Simple questions bypass autopilot automatically:

```
What files handle authentication?
How does the routing work?
Explain the database schema
```

---

## Available Agents

| Agent | Use Case | How to Invoke |
|-------|----------|---------------|
| **autopilot** | Full task execution (explore → implement → verify → review) | Automatic for substantive prompts |
| **autopilot-fixer** | Fix incomplete/broken autopilot output | `Use the autopilot-fixer subagent` |
| **closer** | Final verification + PR notes (no new code) | `Use the closer subagent` |
| **triage** | Debug failures (repro → diagnose → fix) | `Use the triage subagent` |
| **parallel-orchestrator** | Multi-part tasks needing parallel work | `Use the parallel-orchestrator subagent` |

### When Autopilot Doesn't Finish

```
Use the autopilot-fixer subagent.

Original Task:
<<<
[paste your original prompt]
>>>

What's Still Wrong:
<<<
[paste error messages or describe the issue]
>>>
```

### Final Verification Before PR

```
Use the closer subagent.

Acceptance Criteria:
<<<
- [ ] Feature works as described
- [ ] Tests pass
- [ ] No console errors
>>>
```

---

## Session Persistence (Three-File Pattern)

For complex tasks spanning multiple sessions, the kit provides templates to externalize state:

### Setup

```bash
# Create a task directory
mkdir -p .claude/context/my-feature

# Copy templates
cp .claude/context/templates/*.md .claude/context/my-feature/
```

### The Three Files

| File | Purpose | Update Frequency |
|------|---------|------------------|
| `plan.md` | High-level strategy, architecture decisions | Rarely (only when approach changes) |
| `context.md` | Key discoveries, file locations, gotchas | Each session |
| `tasks.md` | Granular checklist of work items | Frequently |

### Resuming Work

When you return to a task, say:

```
Continue working on my-feature. Resume from where we left off.
```

The kit detects "continue" or "resume" and points Claude to your saved state.

---

## Notifications (ntfy.sh)

Get notified on your phone/browser when Claude needs your attention (permission prompts, waiting for input).

After installation, you'll see your subscription URL:

```
Your default ntfy.sh topic: claude-code-yourhostname

Subscribe: https://ntfy.sh/claude-code-yourhostname
```

### Subscribe Options

| Platform | How to Subscribe |
|----------|------------------|
| Browser | Open `https://ntfy.sh/your-topic` and click "Subscribe" |
| Android | Install [ntfy app](https://play.google.com/store/apps/details?id=io.heckel.ntfy) → Add topic |
| iOS | Install [ntfy app](https://apps.apple.com/app/ntfy/id1625396347) → Add topic |
| CLI | `ntfy subscribe your-topic` |

### Custom Topic

```bash
# Environment variable
export CLAUDE_NTFY_TOPIC="my-secret-topic"

# Or config file
mkdir -p ~/.config/claude-code
echo "my-secret-topic" > ~/.config/claude-code/ntfy_topic
```

### Alternative Backends

```bash
# Discord
export CLAUDE_DISCORD_WEBHOOK="https://discord.com/api/webhooks/..."

# Slack
export CLAUDE_SLACK_WEBHOOK="https://hooks.slack.com/services/..."

# Pushover (paid)
export CLAUDE_PUSHOVER_USER="your-user-key"
export CLAUDE_PUSHOVER_TOKEN="your-app-token"
```

---

## Safety Guardrails

### Blocked by Default

| Category | Examples |
|----------|----------|
| Destructive | `rm -rf`, `sudo`, `mkfs`, `dd` |
| Git operations | `git commit`, `git add`, `git push --force` |
| Remote execution | `curl \| bash`, `wget \| sh`, base64 decode to shell |
| Supply chain | `npx [unknown]`, `pip install` from URLs |

### Protected Files (Sentinel Zones)

These require explicit approval:
- `.env` files (except `.env.example`)
- `**/secrets/**`, `**/*credentials*`
- `**/*.pem`, `**/*.key`
- Code with `LEGACY_PROTECTED`, `DO_NOT_MODIFY`, or `SECURITY_CRITICAL` comments

### Override Protection (Use Carefully)

```bash
export CLAUDE_ALLOW_PROTECTED_EDITS=1
claude
```

---

## Directory Structure

```
.claude/
├── CLAUDE.md                 # Constitution (universal rules)
├── settings.local.json       # Permissions + hook config
├── agents/
│   ├── CLAUDE.md             # Agent documentation
│   ├── autopilot.md          # Main task executor
│   ├── autopilot-fixer.md    # Fix-up pass
│   └── ...                   # Other agents
├── hooks/
│   ├── CLAUDE.md             # Hook documentation
│   ├── autopilot_inject.py   # Auto-triggers autopilot
│   ├── guard_bash.py         # Blocks dangerous commands
│   ├── protect_files.py      # Blocks sensitive file edits
│   └── ...                   # Other hooks
├── context/
│   ├── templates/            # Three-file pattern templates
│   └── <task>/               # Your session state (gitignored)
├── docs/                     # Reference documentation
├── logs/                     # Session logs (gitignored)
└── extras/
    ├── doctor.sh             # Validate configuration
    └── install-extras.sh     # Install wshobson agents/commands
```

---

## External Editor (Ctrl+G)

Press `Ctrl+G` in Claude Code to open an external editor for composing prompts.

The kit includes a dynamic `claude-editor` wrapper that automatically detects:
1. VS Code (local install)
2. VS Code Remote-SSH (`~/.vscode-server`)
3. Cursor (VS Code fork)
4. Falls back to nano/vim if no GUI editor found

### VS Code Keybinding Conflict

If `Ctrl+G` opens VS Code's "Go to Recent Directory" picker instead of the editor, add this to your VS Code `keybindings.json`:

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

This unbinds Ctrl+G and rebinds "Go to Recent Directory" to Ctrl+Shift+Alt+P. Alternatively, use `"key": "escape"` to disable the feature completely.

### Manual Editor Override

To use a specific editor, set in `~/.claude/settings.json`:

```json
{
  "env": {
    "EDITOR": "/path/to/your/editor --wait",
    "VISUAL": "/path/to/your/editor --wait"
  }
}
```

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Autopilot not launching | Restart Claude Code after install. Check `.claude/settings.local.json` exists |
| Command blocked | Check `.claude/hooks/guard_bash.py` — add to allowlist if safe |
| File edit blocked | Check for sentinel markers in code. Use `CLAUDE_ALLOW_PROTECTED_EDITS=1` to override |
| Formatting not working | Requires `.prettierrc*` (JS/TS) or `pyproject.toml` (Python) in repo |
| Hooks not running | Copy settings: `cp .claude/settings.local.json .claude/settings.json` |
| Ctrl+G opens nano instead of VS Code | Run: `sudo cp .claude/scripts/claude-editor.sh /usr/local/bin/claude-editor && sudo chmod +x /usr/local/bin/claude-editor` |
| VS Code exited with code 127 | The `code` command is not found. Install `claude-editor` wrapper (see above) |

### Validate Configuration

```bash
./.claude/extras/doctor.sh
```

---

## Installation Options

### Full Bootstrap (Recommended for Linux)

```bash
curl -fsSL https://raw.githubusercontent.com/NorkzYT/claude-code-autopilot/main/install.sh \
  | bash -s -- --repo NorkzYT/claude-code-autopilot --ref main --force --bootstrap-linux
```

Installs: kit + devtools (git, python3, notify-send) + wshobson agents/commands

### Kit Only (No Extras)

```bash
curl -fsSL https://raw.githubusercontent.com/NorkzYT/claude-code-autopilot/main/install.sh \
  | bash -s -- --repo NorkzYT/claude-code-autopilot --ref main --force
```

### Update Existing Install

Run the same install command with `--force` to update while preserving logs.

### Installer Options

| Option | Description |
|--------|-------------|
| `--repo <owner/repo>` | Source repo (required) |
| `--ref <branch\|tag\|sha>` | Git ref (default: main) |
| `--dest <path>` | Destination (default: current directory) |
| `--force` | Overwrite existing `.claude/` (preserves logs) |
| `--bootstrap-linux` | Full bootstrap (devtools + extras) |
| `--no-extras` | Skip wshobson agents/commands |

---

## Project Documentation (llms.txt)

The `llms.txt` standard is a "sitemap for AI" that helps Claude navigate your project. Create one at your project root:

```bash
# Copy the template
cp .claude/docs/llms-txt-template.md ./llms.txt

# Edit to describe YOUR project
```

See `.claude/docs/llms-txt-template.md` for a full template with examples.

---

## Git Hygiene

Add to your `.gitignore`:

```gitignore
.claude/logs/
.claude/context/*
!.claude/context/templates/
.claude/vendor/
```

---

## Customization

| Want to... | Do this... |
|------------|------------|
| Tighten permissions | Edit `permissions.allow` in `.claude/settings.local.json` |
| Allow a blocked command | Add pattern to allowlist in `.claude/hooks/guard_bash.py` |
| Disable auto-formatting | Remove `format_if_configured.py` from PostToolUse hooks |
| Add protected paths | Edit `PROTECTED_GLOBS` in `.claude/hooks/protect_files.py` |
| Disable autopilot auto-launch | Remove `autopilot_inject.py` from UserPromptSubmit hooks |

---

## Optional: wshobson Integration

When installed with `--bootstrap-linux`, you get curated agents from:
- [wshobson/commands](https://github.com/wshobson/commands)
- [wshobson/agents](https://github.com/wshobson/agents)

Usage:
```
/workflows:full-stack-feature build user dashboard
/tools:security-scan src/
```

Manage extras:
```bash
./.claude/extras/install-extras.sh           # Install/update
./.claude/extras/install-extras.sh --update  # Update only
```

---

## Core Principles

1. **Smallest change that satisfies the task** — No drive-by refactors
2. **Discovery first** — Search and read before deciding
3. **Always verify** — Run tests/lint/build or provide manual steps
4. **One bounded retry** — Triage → patch → verify once if it fails
5. **No destructive commands** — Unless explicitly approved
