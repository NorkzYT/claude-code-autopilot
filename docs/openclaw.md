# OpenClaw Setup (Quick Guide)

This page is a short entry point. The full OpenClaw guides live in `.claude/docs/`.

## What OpenClaw Adds

- Discord remote control (slash commands and channel bindings)
- Browser automation (CDP + Docker Chromium)
- Cron jobs and automation
- Gateway and multi-agent routing
- Cross-session memory and search

## Quick Setup

```bash
curl -fsSL https://raw.githubusercontent.com/NorkzYT/claude-code-autopilot/main/install.sh \
  | bash -s -- --repo NorkzYT/claude-code-autopilot --ref main --force --bootstrap-linux --with-openclaw
```

Then follow the prompt output:

1. `claude setup-token`
2. `openclaw models auth paste-token --provider anthropic`
3. `openclaw gateway start`
4. `bash .claude/bootstrap/openclaw_discord_setup.sh` (optional)
5. `bash .claude/bootstrap/add_openclaw_agent.sh <agent-id> <repo-path>` (for extra repos)

## Discord (OpenClaw 2026.2.x)

Use slash commands first:

- `/status`
- `/help`
- `/new`

If `!status` says `bash is disabled`, that is expected on secure setups. Use slash commands and only enable `commands.bash=true` if you want shell passthrough.

## Browser Access to Local Apps

Yes, OpenClaw can verify local frontends and local APIs while you develop.

- If you use the Docker browser container, use `http://host.docker.internal:<port>` from the browser context
- If you use a native browser or relay mode on the host, `http://localhost:<port>` works

Example:

- frontend: `http://host.docker.internal:8080` (Docker browser)
- API: `http://host.docker.internal:3000`

## Hook Model

This repo uses two hook systems:

- `.claude/hooks/*` (Claude Code hooks)
- OpenClaw plugin hooks (`openclaw hooks ...`) for gateway runtime features

The setup script tries to enable supported OpenClaw hooks like:

- `bootstrap-extra-files`
- `session-memory`
- `command-logger`

Plugin-managed hooks are different. They are registered by plugins and appear in `openclaw hooks list` as `plugin:<id>`. You enable or disable the plugin, not the individual plugin-managed hook.

## Local Workflow Wrapper (Recommended)

This repo includes a local workflow wrapper for engineering verification:

```bash
bash .claude/scripts/openclaw-local-workflow.sh --repo /path/to/repo
```

It runs:

1. Build
2. Run local stack
3. Test
4. Confirm (smoke check)

See `docs/openclaw-plugin-hooks.md` for how to wire it into OpenClaw command wrappers and plugin hooks.

## Full OpenClaw Docs in This Repo

- `.claude/README-openclaw.md` — operator quick reference
- `.claude/docs/openclaw-integration.md` — full setup and ops guide
- `.claude/docs/openclaw-commands.md` — CLI and slash command reference
- `.claude/docs/openclaw-remote-commands.md` — Discord pairing, allowlists, bindings, channel routing
