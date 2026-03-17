# OpenClaw Setup (Quick Guide)

This page is a short entry point. The full OpenClaw guides live in `.claude/docs/`.

## What OpenClaw Adds

- Discord remote control (slash commands and channel bindings)
- Browser automation with a Docker-hosted managed browser
- Live browser viewer for manual login and takeover via noVNC
- Cron jobs and automation
- Gateway and multi-agent routing
- Cross-session memory and search

## Quick Setup

```bash
curl -fsSL https://raw.githubusercontent.com/NorkzYT/claude-code-autopilot/main/install.sh \
  | bash -s -- --repo NorkzYT/claude-code-autopilot --ref main --force --bootstrap-linux --with-openclaw
```

Then:

1. Optional overrides: `cp .env.example .env`
2. Start or restart the Docker stack: `openclaw up`
3. Authenticate Anthropic subscription inside the container: `claude setup-token && openclaw models auth paste-token --provider anthropic`
4. Authenticate OpenAI subscription inside the container when needed: `openclaw models auth login --provider openai-codex`
5. Open the browser viewer: `openclaw viewer-url`
6. Run Discord setup if needed: `bash .claude/bootstrap/openclaw_discord_setup.sh`
7. Register extra repos under `/opt/repos` if needed: `openclaw agents add <agent-id> --workspace /opt/repos/<repo-name> --non-interactive`

Important:
- Default repo mount is `${HOST_REPOS_DIR:-/opt/repos}` on the host to `/opt/repos` in the container.
- OpenClaw is not installed on the host in the default flow. The `openclaw` command is a host wrapper into Docker.
- `OPENCLAW_THINKING_DEFAULT=high` is the recommended default when `OPENCLAW_MODEL_PRIMARY=anthropic/claude-sonnet-4-6`.
- Use `ANTHROPIC_API_KEY` or `OPENAI_API_KEY` in `.env` for direct API-key auth. Use in-container auth commands for subscription-backed auth.
- Host OpenClaw state automatically defaults to `~/.openclaw`, bind-mounted into the container. Only set `OPENCLAW_HOST_STATE_DIR` if you want a non-default path.
- `PROJECT.md` is generated only by deep analysis.

## Browser Login and Takeover

Use the noVNC viewer when you need to watch the browser or log into a site manually:

```bash
openclaw viewer-url
```

Open the printed URL in your browser, complete the login in the viewer, then return to OpenClaw commands. The browser profile persists in the host `~/.openclaw` state directory across container restarts.

For OpenAI subscription OAuth inside Docker, run:

```bash
openclaw models auth login --provider openai-codex
```

If the callback flow cannot complete automatically, use OpenClaw's printed fallback prompt to paste the redirect URL or code back into the container session.

## Add a New Repo Agent

```bash
openclaw agents add <agent-id> --workspace <repo-path> --non-interactive
```

## Docker Stack (OpenClaw + Viewer)

Start:

```bash
openclaw up
```

Logs:

```bash
openclaw logs
openclaw status
```

Stop:

```bash
openclaw down
```

Raw Docker Compose form:

```bash
docker compose -f docker-compose.openclaw.yml up -d
```

See:
- `docs/docker-openclaw-crewai.md` for compose details
- `.claude/docs/openclaw-integration.md` for the full Docker-only integration guide
