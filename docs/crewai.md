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

1. Start local proxy container:

```bash
make crewai-proxy-up
```

2. In `.crewai/.env`, keep:

```bash
CREWAI_LLM_MODE=proxy
OPENAI_BASE_URL=http://127.0.0.1:8317/v1
CLI_PROXY_BASE_URL=http://127.0.0.1:8317/v1
CLI_PROXY_API_KEY=<local-proxy-key-from-.crewai/cliproxyapi/config.yaml>
OPENAI_API_KEY=<same-local-proxy-key-or-empty>
```

Set `MARKETING_MODEL` to a model name or alias that exists in your CLIProxyAPI config.
Default scaffold value is `gpt-5.3-codex`.

3. Run CrewAI:

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
- Configure your subscription/provider routing inside CLIProxyAPI itself.
- Ensure your usage complies with the terms of each provider/subscription.

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
