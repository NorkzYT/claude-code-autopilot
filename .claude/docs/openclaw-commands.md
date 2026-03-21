# OpenClaw Commands Reference

> All Claude Code commands and tools related to the OpenClaw integration.
>
> Most commands below have `make` equivalents -- run `make help` to see all available targets.

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

## Discord Commands (Version-Safe)

Use slash commands first on OpenClaw 2026.2.x:

| Command | Description |
|---------|-------------|
| `/status` | Session, model, context, and runtime status |
| `/help` | Available commands |
| `/new` | Start a new session in the current channel/thread |
| `/reset` | Reset current session |
| `/recheckin 5m <task>` | Create a real timed follow-up via OpenClaw cron (plugin command) |

Notes:
- `!status`, `!ship`, and other `!` commands may be custom workflows and are not guaranteed to exist.
- If `!status` returns `bash is disabled`, that means the bot treated it as shell passthrough. Use `/status` instead.
- Enable `commands.bash=true` only if you want direct shell passthrough from Discord.
- Do not promise "I'll check back in X minutes" unless you create a real cron job (use `/recheckin`).

## CLI Commands (Direct)

```bash
# Gateway management
openclaw gateway start                          # make start
openclaw gateway stop                           # make stop
openclaw gateway status
openclaw gateway logs                           # make logs

# Channel management
openclaw channels add --channel discord --token <your-bot-token>
openclaw channels status                        # make channels-status
openclaw channels remove discord

# Auth management
openclaw models auth paste-token --provider anthropic   # make auth-anthropic
openclaw models status                                  # make models-status

# Cron management
openclaw cron list                              # make cron-list
openclaw cron runs                              # make cron-runs
openclaw cron add --name <name> --schedule "<cron>" --command "<cmd>"
openclaw cron enable <name>
openclaw cron disable <name>
openclaw cron remove <name>

# Memory/RAG
openclaw memory search "<query>"                # make memory-search QUERY="<query>"
openclaw memory status                          # make memory-status
openclaw memory reindex                         # make memory-reindex
openclaw memory prune --older-than 30d

# Browser
openclaw browser navigate <url>
openclaw browser screenshot --name <name>
openclaw browser analyze
openclaw browser compare <name1> <name2>
openclaw viewer-url                             # make viewer-url

# Status
openclaw status                                 # make status
openclaw status --usage
openclaw status --usage --json

# Notifications
openclaw notify "<message>"

# Workspace
openclaw workspace set <path>

# Skills
openclaw skills install <name>
openclaw skills list

# Hooks (OpenClaw plugin hooks, separate from .claude/hooks)
openclaw hooks list                             # make hooks-list
openclaw hooks enable bootstrap-extra-files     # make hooks-enable HOOK=bootstrap-extra-files
openclaw hooks enable session-memory            # make hooks-enable HOOK=session-memory
openclaw hooks enable command-logger            # make hooks-enable HOOK=command-logger
```

Notes:
- Hooks listed as `plugin:<id>` are plugin-managed hooks.
- Enable or disable the plugin that owns them. Do not try to enable the plugin-managed hook directly.

## Environment Variables

| Variable | Default | Purpose |
|----------|---------|---------|
| `OPENCLAW_ENABLED` | auto-detect | Force enable/disable |
| `OPENCLAW_HOME` | `~/.openclaw` | Home directory |
| `OPENCLAW_GATEWAY_URL` | `ws://127.0.0.1:18789` | Gateway URL |
| `INSTALL_OPENCLAW` | `0` | Install flag |
| `CLAUDE_COST_ALERT_THRESHOLD` | `5.00` | Session cost alert |
| `CLAUDE_COST_DAILY_ALERT` | `20.00` | Daily cost alert |
