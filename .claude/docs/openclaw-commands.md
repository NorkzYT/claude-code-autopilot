# OpenClaw Commands Reference

> All Claude Code commands and tools related to the OpenClaw integration.

## Tool Commands

| Command | Description |
|---------|-------------|
| `/tools:cost-report` | Token usage and cost breakdown |
| `/tools:openclaw-cron` | Manage cron jobs (install, list, enable/disable) |
| `/tools:openclaw-status` | Full observability dashboard |
| `/tools:memory-search <query>` | Search past session memory |
| `/tools:browser-test [url]` | Visual testing with browser |

## Workflow Commands

| Command | Description |
|---------|-------------|
| `/workflows:openclaw-channels` | Set up Discord and other channels |

## Discord Commands

| Command | Description | Timeout |
|---------|-------------|---------|
| `!ship <task>` | Execute autopilot pipeline | 5 min |
| `!test` | Run test suite | 2 min |
| `!review <PR#>` | Review pull request | 3 min |
| `!status` | Project status | 30 sec |
| `!deploy` | Deployment readiness check | 2 min |
| `!ask <question>` | Query codebase | 1 min |
| `!cron list` | Show cron jobs | 10 sec |
| `!memory <query>` | Search session memory | 15 sec |

## CLI Commands (Direct)

```bash
# Gateway management
openclaw gateway start
openclaw gateway stop
openclaw gateway status
openclaw gateway logs

# Channel management
openclaw channels add discord
openclaw channels status discord
openclaw channels remove discord

# Auth management
openclaw models auth paste-token --provider anthropic
openclaw models status

# Cron management
openclaw cron list
openclaw cron runs
openclaw cron add --name <name> --schedule "<cron>" --command "<cmd>"
openclaw cron enable <name>
openclaw cron disable <name>
openclaw cron remove <name>

# Memory/RAG
openclaw memory search "<query>"
openclaw memory status
openclaw memory reindex
openclaw memory prune --older-than 30d

# Browser
openclaw browser navigate <url>
openclaw browser screenshot --name <name>
openclaw browser analyze
openclaw browser compare <name1> <name2>

# Status
openclaw status
openclaw status --usage
openclaw status --usage --json

# Notifications
openclaw notify "<message>"

# Workspace
openclaw workspace set <path>

# Skills
openclaw skills install <name>
openclaw skills list
```

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `OPENCLAW_ENABLED` | auto-detect | Force enable/disable |
| `OPENCLAW_HOME` | `~/.openclaw` | Home directory |
| `OPENCLAW_GATEWAY_URL` | `ws://127.0.0.1:18789` | Gateway URL |
| `INSTALL_OPENCLAW` | `0` | Install flag |
| `CLAUDE_COST_ALERT_THRESHOLD` | `5.00` | Session cost alert |
| `CLAUDE_COST_DAILY_ALERT` | `20.00` | Daily cost alert |
