# OpenClaw Integration Guide

> Docker-only setup guide for integrating OpenClaw with Claude Code Autopilot.

## Prerequisites

- Docker + Docker Compose plugin
- Claude Code Autopilot installed (`.claude/` directory present)
- Host repos stored under `/opt/repos` by default, or another path via `HOST_REPOS_DIR`
- Optional: Discord bot token if you want remote Discord control

## Installation

### During initial install

```bash
curl -fsSL https://raw.githubusercontent.com/NorkzYT/claude-code-autopilot/main/install.sh \
  | bash -s -- --repo NorkzYT/claude-code-autopilot --ref main --force --bootstrap-linux --with-openclaw
```

### What this does

- installs Docker-based OpenClaw assets into the repo
- installs a lightweight host wrapper at `~/.local/bin/openclaw`
- prepares the `openclaw-gateway` and `openclaw-browser-viewer` containers
- mounts `${HOST_REPOS_DIR:-/opt/repos}` into the gateway at `/opt/repos`
- bind-mounts host OpenClaw state from `~/.openclaw` into the container by default
- does not install the real OpenClaw CLI on the host

## Environment Configuration

Copy `.env.example` to `.env` if you need overrides:

```bash
cp .env.example .env
```

The example file includes:
- Docker mount and port settings
- git author and committer identity
- optional provider env vars (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`)
- optional Anthropic setup token seed field (`OPENCLAW_ANTHROPIC_SETUP_TOKEN`)
- `OPENCLAW_THINKING_DEFAULT=high` for `anthropic/claude-sonnet-4-6`
- `OPENCLAW_DISCORD_TOKEN`
- browser width, height, and viewer settings

`OPENCLAW_HOST_STATE_DIR` is optional. If you do not set it, the Docker stack automatically uses `~/.openclaw` on the host.

The setup script does not force-start the stack before `.env` is ready. In interactive runs it asks first; if `.env` does not exist yet, it skips startup and tells you to run `openclaw up` after editing `.env`.

## Daily Commands

The host `openclaw` command is a wrapper into the gateway container.

```bash
openclaw up
openclaw down
openclaw logs
openclaw status
openclaw shell
openclaw viewer-url
```

Raw compose form:

```bash
docker compose -f docker-compose.openclaw.yml up -d
```

Host-local services:
- the gateway container can reach host services at `host.docker.internal`
- example: a host app running on port `8080` should be accessed from OpenClaw as `http://host.docker.internal:8080`

Control UI pairing:
- `127.0.0.1` is auto-approved
- the gateway host's own Tailnet address can count as local in current OpenClaw protocol/security docs
- other Tailnet peers and LAN clients still require explicit device approval

## Model Authentication

Authenticate from inside the container through the wrapper.

Anthropic subscription:

```bash
claude setup-token
openclaw models auth paste-token --provider anthropic
openclaw models status
```

OpenAI subscription OAuth:

```bash
openclaw models auth login --provider openai-codex
```

Direct API-key mode:
- set `ANTHROPIC_API_KEY` in `.env` for Anthropic API-key auth
- set `OPENAI_API_KEY` in `.env` for OpenAI API-key auth

You can also pre-seed Anthropic setup-token auth with `OPENCLAW_ANTHROPIC_SETUP_TOKEN` in `.env`, but interactive pasting is preferred.

## Browser Automation and Manual Login

The gateway container runs Chromium on a virtual display. The browser viewer service exposes a noVNC URL so you can watch the session or take over manually.

```bash
openclaw viewer-url
```

Typical flow:
1. start the stack with `openclaw up`
2. open the viewer URL in your desktop browser
3. complete login or 2FA in the viewer
4. return to OpenClaw commands once the session is authenticated

The browser profile persists in the host OpenClaw state directory, so cookies survive restarts and remain visible under `~/.openclaw`.

When `OPENCLAW_MODEL_PRIMARY=anthropic/claude-sonnet-4-6`, the container sets `agents.defaults.thinkingDefault=high` unless you override `OPENCLAW_THINKING_DEFAULT`.

## Discord Setup

Run the existing setup scripts after the stack is up:

```bash
bash .claude/bootstrap/openclaw_discord_setup.sh
bash .claude/bootstrap/openclaw_discord_scale_setup.sh
```

These scripts now work through the Docker-backed `openclaw` wrapper.

## Multi-Repo Setup

Register additional repos mounted under `/opt/repos`:

```bash
openclaw agents add <agent-name> --workspace /opt/repos/<repo-name> --non-interactive
```

## Troubleshooting

| Issue | Solution |
|------|----------|
| `openclaw: command not found` | Open a new shell or ensure `~/.local/bin` is on `PATH` |
| `openclaw` still points to a deleted fnm/npm path | Run `hash -r` or start a new shell; the old command path is usually just cached by the current shell |
| Install finished before I could edit `.env` | Current setup should no longer auto-start before `.env` is ready; if needed, set `OPENCLAW_AUTO_START=no` to force skip |
| Stack not starting | `docker compose -f docker-compose.openclaw.yml logs` |
| Browser viewer blank | Check `openclaw logs` and confirm `openclaw-browser-viewer` is running |
| Gateway cannot see repos | Verify `HOST_REPOS_DIR` and that the repos exist under the mounted path |
| Gateway cannot reach a host dev server | Use `http://host.docker.internal:<port>` instead of `http://localhost:<port>` |
| Git commits use wrong identity | Set `GIT_AUTHOR_*` and `GIT_COMMITTER_*` in `.env`, then restart with `openclaw up` |
