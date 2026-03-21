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

The Docker/OpenClaw install defaults to `/opt/openclaw-home` when `--dest` is omitted.

1. Optional overrides: `cp /opt/openclaw-home/.env.example /opt/openclaw-home/.env`
2. Edit `/opt/openclaw-home/.env` before first startup
3. Start or restart the Docker stack from `/opt/openclaw-home`: `make start`
4. Authenticate Anthropic subscription inside the container: `make auth-anthropic`
5. Authenticate OpenAI subscription inside the container when needed: `make auth-openai`
6. Open the browser viewer: `make viewer-url`
7. Run Discord setup if needed: `make setup-discord`
8. Register extra repos under `/opt/repos` if needed: `make add-agent AGENT=<agent-id> REPO=/opt/repos/<repo-name>`

Important:
- Default repo mount is `${HOST_REPOS_DIR:-/opt/repos}` on the host to `/opt/repos` in the container.
- OpenClaw is not installed on the host in the default flow. The `openclaw` command is a host wrapper into Docker.
- `OPENCLAW_THINKING_DEFAULT=high` is the recommended default when `OPENCLAW_MODEL_PRIMARY=anthropic/claude-sonnet-4-6`.
- Use `ANTHROPIC_API_KEY` or `OPENAI_API_KEY` in `.env` for direct API-key auth. Use in-container auth commands for subscription-backed auth.
- Host OpenClaw state automatically defaults to `~/.openclaw`, bind-mounted into the container. Only set `OPENCLAW_HOST_STATE_DIR` if you want a non-default path.
- Host services are reachable from the container at `http://host.docker.internal:<port>`. For example, a host dev server on port `8080` should be accessed as `http://host.docker.internal:8080` from OpenClaw.
- Control UI pairing: `127.0.0.1` is auto-approved. Same-host Tailnet access may also count as local, but other Tailnet/LAN clients still require explicit device approval.
- `PROJECT.md` is generated only by deep analysis.

## Browser Login and Takeover

Use the noVNC viewer when you need to watch the browser or log into a site manually:

```bash
make viewer-url
```

Open the printed URL in your browser, complete the login in the viewer, then return to OpenClaw commands. The browser profile persists in the host `~/.openclaw` state directory across container restarts.

For OpenAI subscription OAuth inside Docker, run:

```bash
make auth-openai
```

If the callback flow cannot complete automatically, use OpenClaw's printed fallback prompt to paste the redirect URL or code back into the container session.

## Add a New Repo Agent

```bash
make add-agent AGENT=<agent-id> REPO=<repo-path>
```

## Docker Stack (OpenClaw + Viewer)

Start:

```bash
make start
```

Logs:

```bash
make logs
make status
```

Stop:

```bash
make stop
```

Raw Docker Compose form:

```bash
docker compose -f docker-compose.openclaw.yml up -d
```

See:
- `docs/docker-openclaw-crewai.md` for compose details
- `.claude/docs/openclaw-integration.md` for the full Docker-only integration guide
