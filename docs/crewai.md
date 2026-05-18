# CrewAI Setup and Workflow

This guide explains how to use the CrewAI integration added by `--with-crewai`.

## What `--with-crewai` Adds

- Runs `.claude/bootstrap/crewai_setup.sh`
- Scaffolds `.crewai/` with:
  - Crew agents and tasks config
  - Python entrypoints for execution
  - Report artifact generation
- Adds local runner:
  - `.claude/scripts/crewai-local-workflow.sh`

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/NorkzYT/claude-code-autopilot/main/install.sh \
  | bash -s -- --repo NorkzYT/claude-code-autopilot --ref main --force --bootstrap-linux --with-crewai
```

You can combine with OpenClaw:

```bash
curl -fsSL https://raw.githubusercontent.com/NorkzYT/claude-code-autopilot/main/install.sh \
  | bash -s -- --repo NorkzYT/claude-code-autopilot --ref main --force --bootstrap-linux --with-openclaw --with-crewai
```

## Initial Setup

```bash
cd .crewai
cp .env.example .env
# choose direct API mode or proxy mode in .env
uv sync
```

## Run Commands

Default CrewAI run:

```bash
cd .crewai
uv run crewai run
```

Run through wrapper with goal override:

```bash
make crewai-workflow GOAL="Subscriber growth plan"
# Or directly: bash .claude/scripts/crewai-local-workflow.sh --goal "Subscriber growth plan"
```

Run through wrapper and auto-start local CLIProxyAPI:

```bash
bash .claude/scripts/crewai-local-workflow.sh --with-proxy --goal "Subscriber growth plan"
```

Dry-run without calling an LLM:

```bash
bash .claude/scripts/crewai-local-workflow.sh --dry-run
```

## Generated Artifacts

Each run writes:

- `.crewai/reports/go-to-market-plan.md`
- `.crewai/reports/experiment-backlog.csv`
- `.crewai/reports/weekly-ops.md`
- `.crewai/outputs/run-<timestamp>.json`

## Default Marketing Crew

The scaffold includes five default agents:

- `market_researcher`
- `positioning_copywriter`
- `channel_strategist`
- `funnel_analyst`
- `weekly_operator`

And a sequential task flow:

1. Define ICP
2. Craft positioning
3. Plan channels
4. Design funnel metrics
5. Build weekly execution plan

## CLIProxyAPI Mode (Subscription-Backed)

If you want CrewAI to route through local OpenAI-compatible proxy instead of direct provider API keys:

### Step 1 — Start the proxy container

```bash
make crewai-proxy-up
# or: bash .claude/scripts/crewai-cliproxyapi.sh up
```

### Step 2 — Log in to your Codex subscription (one-time)

CLIProxyAPI v7+ ships two Codex auth flows. Pick one:

**OAuth (recommended — requires a browser on the same machine):**

```bash
docker exec -it cliproxyapi ./CLIProxyAPI -codex-login
```

Opens a browser tab to accounts.openai.com. Sign in with the ChatGPT account that
holds your Plus, Pro, Business, or Enterprise plan. The callback lands on
`localhost:1455` or `localhost:54545` (both are mapped in the compose file).

**Device code (headless / no local browser):**

```bash
docker exec -it cliproxyapi ./CLIProxyAPI -codex-device-login
```

Prints a short code and a URL you open on any device. No callback redirect needed.

Both flows write OAuth state to the `auths/` volume (`./tmp/cliproxyapi/auths` on host
by default). The running server picks it up immediately and auth survives container restarts.

Verify the login worked:

```bash
# grab the proxy key from your config
PROXY_KEY=$(grep -A1 'api-keys' .crewai/cliproxyapi/config.yaml | tail -1 | tr -d ' -"')
curl -s -H "Authorization: Bearer $PROXY_KEY" http://127.0.0.1:8317/v1/models | python3 -m json.tool | head -20
```

You should see Codex / GPT model entries in the response.

### Step 3 — Configure `.crewai/.env`

```bash
CREWAI_LLM_MODE=proxy
OPENAI_BASE_URL=http://127.0.0.1:8317/v1
CLI_PROXY_BASE_URL=http://127.0.0.1:8317/v1
CLI_PROXY_API_KEY=<key from .crewai/cliproxyapi/config.yaml api-keys list>
OPENAI_API_KEY=<same key>
MARKETING_MODEL=gpt-5.3-codex
```

`MARKETING_MODEL` must match a model name returned by `/v1/models`.
After login the proxy exposes whatever Codex reports — check the `curl` output above.

### Step 4 — Run CrewAI

```bash
bash .claude/scripts/crewai-local-workflow.sh --with-proxy
```

Helper commands:

```bash
make crewai-proxy-status
bash .claude/scripts/crewai-cliproxyapi.sh logs
make crewai-proxy-down
```

Notes:
- Ensure your usage complies with OpenAI's terms of service for your subscription tier.
- CLIProxyAPI supports multi-account round-robin; add additional `auths/` entries to
  spread load across accounts if one plan's rate limits are hit.

## Running CrewAI in Its Own Container

Start stack:

```bash
docker compose -f docker-compose.crewai.yml up -d crewai-runner
```

Run a repo workflow in the CrewAI container:

```bash
docker exec -it crewai-runner crewai-entrypoint run /opt/repos/<repo-name> --goal "Increase traction and paying customers"
```

The compose stack mounts host `/opt/repos` into the container at `/opt/repos`.

Optional proxy profile:

```bash
docker compose -f docker-compose.crewai.yml --profile proxy up -d cliproxyapi
```

## Troubleshooting

- `uv: command not found`
  - Install `uv`, then rerun `cd .crewai && uv sync`.
- `No LLM provider key found`
  - Add a provider key in `.crewai/.env` or run with `--dry-run`.
- `crewai run` fails
  - Use wrapper fallback:
    - `make crewai-workflow GOAL="Your goal"`
