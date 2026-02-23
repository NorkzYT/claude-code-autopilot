# OpenClaw Quick Reference

This repo is OpenClaw-first. These are the most useful commands and scripts after install.

## Core Commands

Start / restart gateway:

```bash
openclaw gateway start
```

Check status:

```bash
openclaw status
openclaw dashboard
```

Authenticate Anthropic (Claude Max / token):

```bash
claude setup-token
openclaw models auth paste-token --provider anthropic
```

Set model (example: Sonnet-first):

```bash
openclaw models set anthropic/claude-sonnet-4-6
openclaw gateway start
```

## Bootstrap Scripts (`.claude/bootstrap/`)

Register a repo as an OpenClaw agent (most important):

```bash
bash .claude/bootstrap/add_openclaw_agent.sh <agent-id> <repo-path>
```

Example:

```bash
bash .claude/bootstrap/add_openclaw_agent.sh kairo /opt/github/Kairo
```

What it does:
- registers the agent in OpenClaw
- creates/updates `.openclaw/*` persona files
- runs repo analysis (`TOOLS.md`, `HEARTBEAT.md`, `PROJECT.md`)
- converts Claude skills into `.openclaw/skills`
- creates Codex compatibility files (`AGENTS.md`, `.agents/skills`, `.codex/rules`)
- updates `.gitignore` for local agent/runtime files

Useful flags:

```bash
--no-restart
--skip-persona
--skip-skills
--skip-codex
```

Set up Discord bot channel:

```bash
bash .claude/bootstrap/openclaw_discord_setup.sh
```

Set up OpenClaw browser container / CDP:

```bash
bash .claude/bootstrap/openclaw_browser_setup.sh
```

Run repo analysis manually:

```bash
bash .claude/bootstrap/analyze_repo.sh <repo-path>
bash .claude/bootstrap/analyze_repo.sh <repo-path> --deep
```

## Discord Notes (OpenClaw 2026.2.x)

- Prefer slash commands in Discord: `/status`, `/help`, `/new`
- `!status` / `!ask` may not be built-in on newer OpenClaw versions
- DM pairing and server-channel authorization are separate
- Server channels may require allowlist entries for:
  - guild ID
  - channel ID
  - your Discord user ID

## Tailscale / Remote Dashboard

- Preferred: Tailscale Serve (HTTPS) + loopback gateway
- If setup cannot enable Serve automatically:

```bash
sudo tailscale set --operator=$USER
tailscale serve --bg http://127.0.0.1:18789
```

- First secure UI connect may require device pairing:

```bash
openclaw devices list
openclaw devices approve <requestId>
```

## Updating Existing Repos

Refresh `.claude/` only (no OpenClaw bootstrap rerun):

```bash
curl -fsSL https://raw.githubusercontent.com/NorkzYT/claude-code-autopilot/main/install.sh \
  | bash -s -- --repo NorkzYT/claude-code-autopilot --ref main --force --bootstrap-linux
```

Re-run OpenClaw bootstrap / regenerate `.openclaw/*`:

```bash
curl -fsSL https://raw.githubusercontent.com/NorkzYT/claude-code-autopilot/main/install.sh \
  | bash -s -- --repo NorkzYT/claude-code-autopilot --ref main --force --bootstrap-linux --with-openclaw
```

