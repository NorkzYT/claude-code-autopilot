# OpenClaw Integration Guide

> Complete setup guide for integrating OpenClaw with Claude Code Autopilot.

## Prerequisites

- **Node.js 22+** (OpenClaw requirement)
- **Claude Max subscription** ($200/month — unlimited usage)
- **Discord server** (optional, for remote access)
- **Claude Code Autopilot** installed (`.claude/` directory present)

## Phase 1: Installation

### Option A: During Initial Install

```bash
curl -fsSL https://raw.githubusercontent.com/NorkzYT/claude-code-autopilot/main/install.sh \
  | bash -s -- --repo NorkzYT/claude-code-autopilot --ref main --force --bootstrap-linux --with-openclaw
```

### Option B: Add to Existing Installation

```bash
# Install OpenClaw globally
npm install -g openclaw@latest

# Run the setup script
bash .claude/bootstrap/openclaw_setup.sh
```

### What Gets Installed

- `openclaw` CLI tool (global npm package)
- `~/.openclaw/` directory with configuration
- OpenClaw configuration (via `openclaw config set` commands)
- `~/.openclaw/AGENTS.md` (agent operating instructions)
- `~/.openclaw/HEARTBEAT.md` (health check template)
- Recommended OpenClaw skill during base setup (github). Discord skill is bundled and becomes ready after `openclaw channels add --channel discord --token <your-bot-token>` (or the Discord setup script) configures a token.
- Recommended OpenClaw plugin hooks (if supported): `bootstrap-extra-files`, `session-memory`, `command-logger`
- `OPENCLAW_HOME` environment variable in shell profiles
- Project `.gitignore` entries for local agent/runtime state:
  - `.claude/`, `.codex/`, `.codex-home/`, `.agents/`, `.openclaw/`, root `AGENTS.md` shim
- Automatic agent registration attempt during install (`OPENCLAW_AUTO_REGISTER=1`)

### Hook Systems (Important)

This project uses two hook systems:

- `.claude/hooks/*` for Claude Code prompt/tool guardrails and logging
- `openclaw hooks ...` for gateway runtime hooks (memory sync, bootstrap extra files, command logging)

They are separate and can be used together.

## Phase 2: Claude Max Authentication

Claude Max provides unlimited usage at a flat $200/month rate. No per-token billing.

```bash
# Step 1: Generate a setup token from Claude
claude setup-token

# Step 2: Paste the token into OpenClaw
openclaw models auth paste-token --provider anthropic

# Step 3: Verify authentication
openclaw models status
# Should show: Anthropic — Active (Claude Max)
```

### Token Refresh

Setup tokens may expire. To refresh:
```bash
claude setup-token
openclaw models auth paste-token --provider anthropic
```

## Phase 3: Discord Setup

### Create Discord Bot

1. Go to [Discord Developer Portal](https://discord.com/developers/applications)
2. Click **New Application** → Name it "Claude Code Autopilot"
3. Go to **Bot** → **Add Bot**
4. Enable **MESSAGE CONTENT INTENT** under Privileged Gateway Intents
5. Click **Reset Token** → Copy the token

### Invite Bot to Server

1. Go to **OAuth2** → **URL Generator**
2. Check scopes: `bot`, `applications.commands`
3. Check permissions: Send Messages, Read Message History, Embed Links, Attach Files
4. Open the generated URL → Select your server → Authorize

### Connect to OpenClaw

```bash
# Interactive setup
bash .claude/bootstrap/openclaw_discord_setup.sh

# Or manual setup
openclaw plugins enable discord
openclaw channels add --channel discord --token <your-bot-token>
openclaw gateway restart

# Test connection
openclaw notify "Hello from Claude Code Autopilot!"
```

### Discord Commands Reference

See `.claude/docs/openclaw-remote-commands.md` for the full guide.

Quick reference (OpenClaw 2026.2.x):
- `/status` — Status overview
- `/help` — Available commands
- `/new` — Start a fresh session in the current channel/thread

Notes:
- Prefer slash commands.
- `!status`, `!ship`, and other `!` commands are not guaranteed built-ins.
- If `!status` returns `bash is disabled`, use `/status` or enable `commands.bash=true` only if you want shell passthrough.

## Phase 4: Cron Scheduling

### Install Pre-configured Jobs

```bash
# Install all pre-configured cron jobs
/tools:openclaw-cron install

# Or manually
openclaw cron add --name "nightly-tests" --schedule "0 2 * * *" --command "exec npm test"
```

### Pre-configured Jobs

| Job | Schedule | Description |
|-----|----------|-------------|
| `nightly-tests` | 2 AM daily | Full test suite |
| `dep-audit-weekly` | Monday 9 AM | Dependency security audit |
| `cost-summary-daily` | 6 PM daily | Token usage summary |
| `heartbeat` | Every 30min (8AM-midnight) | Health check (disabled by default) |

### Managing Jobs

```bash
openclaw cron list          # Show all jobs
openclaw cron runs          # Show recent runs
openclaw cron enable <name> # Enable a job
openclaw cron disable <name># Disable a job
```

### Enable Heartbeat

The heartbeat monitors git status, tests, dependencies, and system health every 30 minutes during active hours. It only reports to Discord when issues are found.

```bash
/tools:openclaw-cron heartbeat on
```

## Phase 5: Cross-Session Memory

### How It Works

1. When a Claude Code session ends, the Stop hook syncs session state to OpenClaw:
   - `.claude/context/<task>/plan.md`
   - `.claude/context/<task>/context.md`
   - `.claude/context/<task>/tasks.md`
2. OpenClaw indexes these files into SQLite with hybrid search (70% vector + 30% BM25)
3. You can search past sessions using RAG

### Searching Memory

```bash
# From Claude Code
/tools:memory-search "how did we fix the auth bug"

# From Discord (if your server has a custom memory command)
# example: !memory "database migration approach"

# From CLI
openclaw memory search "session state pattern"
```

### Memory Maintenance

```bash
# Check memory index status
openclaw memory status

# Rebuild index
openclaw memory reindex

# Clear old sessions
openclaw memory prune --older-than 30d
```

## Phase 6: Browser Automation

### Prerequisites

- Chromium or Chrome installed (OpenClaw auto-manages via CDP)
- Browser enabled in config: `"browser": {"enabled": true}`

### Visual Testing

```bash
# From Claude Code
/tools:browser-test http://localhost:3000

# From Discord
/new
# Ask the agent to use browser tooling to capture a screenshot of the login page
```

### Viewport Testing

```bash
/tools:browser-test http://localhost:3000 responsive
```

## Phase 7: Observability

### Full Dashboard

```bash
/tools:openclaw-status
```

Shows: gateway status, Discord connection, token usage, cron jobs, heartbeat, memory index.

### Statusline Indicator

The Claude Code statusline shows a compact OpenClaw indicator:
- `OC:OK` — Gateway running (green)
- `OC:OFF` — Gateway stopped (yellow)
- Not shown if OpenClaw not installed

## Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| `openclaw: command not found` | `npm install -g openclaw@latest` |
| Gateway won't start | Check port 18789 is free: `lsof -i :18789` |
| Discord bot offline | Verify token: `openclaw channels status discord` |
| Auth expired | Re-run: `claude setup-token` then paste into OpenClaw |
| Memory search empty | Check sync: `openclaw memory status` |
| Browser test fails | Ensure Chromium installed: `which chromium` or `which google-chrome` |
| Cron jobs not running | Check: `openclaw cron list` — ensure jobs are enabled |
| High token usage alerts | Informational only on Claude Max (flat rate) |

### Checking Logs

```bash
# OpenClaw gateway logs
openclaw gateway logs

# Cost tracker logs
cat .claude/logs/cost-tracker.log

# Tool audit logs
cat .claude/logs/tool-audit.log
```

### Resetting Configuration

```bash
# Reset OpenClaw config to template defaults
cp .claude/templates/openclaw.json ~/.openclaw/openclaw.json

# Reconfigure workspace
openclaw workspace set "$(pwd)"
```

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `OPENCLAW_ENABLED` | auto-detect | Force enable/disable OpenClaw features |
| `OPENCLAW_HOME` | `~/.openclaw` | OpenClaw home directory |
| `OPENCLAW_GATEWAY_URL` | `ws://127.0.0.1:18789` | Gateway WebSocket URL |
| `INSTALL_OPENCLAW` | `0` | Bootstrap flag for install |
| `CLAUDE_COST_ALERT_THRESHOLD` | `5.00` | Per-session cost alert |
| `CLAUDE_COST_DAILY_ALERT` | `20.00` | Daily cost alert |

## Architecture

```
Claude Code Autopilot          OpenClaw Platform
┌─────────────────────┐       ┌──────────────────────┐
│ .claude/hooks/      │       │ Gateway (port 18789) │
│   (Claude Code)     │       │                      │
│                     │       │ Discord Bot          │
│ .claude/context/    │──────▶│ Memory/RAG (SQLite)  │
│   plan.md           │       │ Browser (CDP)        │
│   context.md        │       │                      │
│   tasks.md          │       │ Cost Tracking        │
└─────────────────────┘       │ Plugin Hooks         │
        │                     │ (OpenClaw gateway)   │
        └────────────────────▶└──────────────────────┘
         │                              │
         └──────── Discord ◀────────────┘
                   /status, /help, /new
```

## Phase 8: Autonomous Engineering Mode

### Overview

Autonomous mode allows Claude Code to work unattended for local engineering tasks — fixing code, running local build/test steps, and committing changes on feature branches. It is activated by the `OPENCLAW_AUTONOMOUS=1` environment variable.

### Enabling Autonomous Mode

```bash
# Via environment variable (for cron/scripts)
OPENCLAW_AUTONOMOUS=1 claude --print "task description"

# Via Discord
# Start a session, then give the task in chat. Slash commands manage the session.

# Via cron (see .claude/templates/cron-jobs.json)
# data-verification and api-discovery jobs are pre-configured
```

### Security Model

| Command | Interactive | Autonomous |
|---------|------------|------------|
| `sudo`, `rm -rf` | BLOCKED | BLOCKED |
| `curl \| bash` | BLOCKED | BLOCKED |
| `curl <url>` | BLOCKED | ALLOWED |
| `git commit` | BLOCKED | ALLOWED (feature branch) |
| `git push main` | BLOCKED | BLOCKED |
| `git push branch` | BLOCKED | ALLOWED |
| `npm install` | BLOCKED | ALLOWED |
| `Co-Authored-By` | BLOCKED | BLOCKED |

### Browser Authentication

For automated tasks that require website access:

1. **Manual login once** in headed mode: `openclaw browser launch --headed`
2. **Export cookies:** `openclaw browser cookies export --domain <domain>`
3. **Store in vault:** `openclaw vault set <site>.cookies <path>`

Automated tasks import cookies before accessing authenticated pages. See `.claude/skills/openclaw-browser/LOGIN_PATTERNS.md`.

### Chrome Extension Testing

Use Extension Relay mode to test extensions in a real Chrome instance:

1. Create dedicated Chrome profile for automation
2. Install extensions in that profile
3. Install OpenClaw Browser Relay extension
4. Configure relay to connect to gateway

See `.claude/skills/openclaw-browser/EXTENSION_TESTING.md` for full guide.

### Git Commit Policy

- All autonomous commits go on professional feature branches (`fix/<name>`, `feat/<name>`, `chore/<name>`)
- NEVER include `Co-Authored-By` lines in commit messages -- commits must appear as the user's own
- Conventional commit format (`feat:`, `fix:`, `chore:`)
- After work is complete, a PR is created for user review
- Direct pushes to main/master are blocked

### Autonomous Cron Jobs

| Job | Schedule | Description |
|-----|----------|-------------|
| `data-verification` | 3 AM daily | Compare scraped vs live data, fix discrepancies |
| `api-discovery` | 4 AM Monday | Capture HAR files, document API patterns |

Enable: `openclaw cron enable data-verification`

### Discord Commands (Autonomous)

Use slash commands for session control (`/new`, `/status`) and then send the task prompt in chat.
Custom `!` workflows can be added, and they are not required for autonomous mode.

### Multi-Workspace Setup

```bash
# Add additional workspaces
openclaw workspace add <name> <path>

# Switch between workspaces
openclaw workspace set <name>
# or use channel bindings so each Discord channel routes to the right agent/workspace

# List all workspaces
openclaw workspace list
```

## Phase 9: Agent Onboarding

### Overview

The `add_openclaw_agent.sh` script automates all steps needed to register a project directory as an OpenClaw agent. It replaces the 10+ manual steps previously required.

### Usage

```bash
bash .claude/bootstrap/add_openclaw_agent.sh <agent-name> <workspace-path> [options]
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `--name <display-name>` | Display name | Capitalized agent-name |
| `--emoji <emoji>` | Agent emoji | 🔧 |
| `--skip-persona` | Don't create persona files | - |
| `--skip-skills` | Don't create skills directory | - |
| `--skip-codex` | Don't create Codex compatibility files | - |
| `--no-restart` | Don't restart the gateway | - |

### Example

```bash
# Register the Kairo project
bash .claude/bootstrap/add_openclaw_agent.sh kairo /opt/github/Kairo --name "Kairo" --emoji "🔧"
```

### What It Does

The script performs 12 idempotent steps:

1. **Validation** -- Checks agent name format, workspace exists, `openclaw` CLI available
2. **Register agent** -- `openclaw agents add` (skips if already registered)
3. **Copy auth** -- Copies `auth.json` + `auth-profiles.json` from existing agent (skips if present)
4. **Config sync** -- Adds agent to both `~/.openclaw/openclaw.json` and `~/.openclaw/.openclaw/openclaw.json`
5. **Create persona** -- Generates AGENTS.md, SOUL.md, USER.md, IDENTITY.md, TOOLS.md, HEARTBEAT.md, BOOTSTRAP.md from templates
6. **Git commit guard** -- Installs repo `commit-msg` hook to block `Co-Authored-By` trailers
7. **Workspace state** -- Creates `.openclaw/workspace-state.json` in workspace root
8. **Skills directory** -- Creates `skills/` directory for OpenClaw skill discovery
9. **Skill conversion** -- Converts `.claude/skills/*/SKILL.md` to OpenClaw format with YAML frontmatter
10. **Workspace `.gitignore` sync** -- Adds local agent/runtime paths and generated root OpenClaw files so they stay local
11. **Codex compatibility** -- Creates root `AGENTS.md` shim, `.codex/rules/default.rules`, and links `.agents/skills` to `.openclaw/skills`
12. **Gateway restart** -- Restarts the gateway to pick up new agent

### Persona Templates

Templates live in `.claude/templates/agent-persona/` and use placeholder variables:

| Placeholder | Description |
|-------------|-------------|
| `{{AGENT_NAME}}` | Lowercase agent identifier (e.g., `kairo`) |
| `{{DISPLAY_NAME}}` | Human-readable name (e.g., `Kairo`) |
| `{{WORKSPACE_PATH}}` | Absolute path to workspace |
| `{{EMOJI}}` | Agent emoji |

### Skills Discovery

Skills are stored in `{workspace}/.openclaw/skills/` and registered via `skills.load.extraDirs` in the OpenClaw config. Each skill must have YAML frontmatter:

```yaml
---
name: skill-name
description: "What this skill does"
---
```

The script automatically converts Claude Code skills (from `.claude/skills/`) to OpenClaw format in `.openclaw/skills/`.

### Codex Compatibility Layer

To support OpenAI Codex and Claude/OpenClaw with minimal duplication, the bootstrap creates:

- `AGENTS.md` at workspace root (thin Codex discovery shim)
- `.agents/skills` symlink to `.openclaw/skills`
- `.codex/rules/default.rules` aligned with `.claude/hooks/guard_bash.py`
- Optional project-local Codex runtime state in `.codex-home/` (via `ccx` alias)

This keeps shared instructions and skills modular while preserving OpenClaw-native layout.

### Usage Optimization (Sonnet First)

The default bundle is configured for cost efficiency:

- Claude defaults to **Sonnet** for planning and most implementation work
- Complex multi-file/architectural tasks escalate to Opus-capable autopilot specialists
- Browser/HAR/vision work is kept explicit to avoid accidental usage spikes

### Config Sync (Root Cause Fix)

The "unknown agent id" bug occurs when the agent exists in one config file but not the other. The script ensures the agent entry exists in **both**:

- `~/.openclaw/openclaw.json` (gateway reads this)
- `~/.openclaw/.openclaw/openclaw.json` (CLI state reads this)

### Idempotency

Running the script multiple times is safe. Each section checks for existing state before making changes and prints "already exists, skipping" messages for items that don't need updating.
