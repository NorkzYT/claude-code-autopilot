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
- `~/.openclaw/openclaw.json` (Claude Max optimized config)
- `~/.openclaw/AGENTS.md` (agent operating instructions)
- `~/.openclaw/HEARTBEAT.md` (health check template)
- Recommended ClawHub skills (github, docker, monitoring)
- `OPENCLAW_HOME` environment variable in shell profiles

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
openclaw channels add discord --token <your-bot-token>

# Test connection
openclaw notify "Hello from Claude Code Autopilot!"
```

### Discord Commands Reference

See `.claude/docs/openclaw-remote-commands.md` for the full command reference.

Quick reference:
- `!ship <task>` — Execute autopilot pipeline
- `!test` — Run tests
- `!review <PR#>` — Review PR
- `!status` — Status overview
- `!ask <question>` — Query codebase

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

# From Discord
!memory "database migration approach"

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
!ship "Take a screenshot of the login page and check for visual issues"
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
│ .claude/hooks/      │──────▶│ Gateway (port 18789) │
│   cost_tracker.py   │       │                      │
│   memory_sync.py    │       │ Discord Bot          │
│                     │       │ Cron Scheduler       │
│ .claude/context/    │──────▶│ Memory/RAG (SQLite)  │
│   plan.md           │       │ Browser (CDP)        │
│   context.md        │       │                      │
│   tasks.md          │       │ Cost Tracking        │
└─────────────────────┘       └──────────────────────┘
         │                              │
         └──────── Discord ◀────────────┘
                   !ship, !test, !status
```
