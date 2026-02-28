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
# set at least one provider key (for example OPENAI_API_KEY or ANTHROPIC_API_KEY)
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
bash .claude/scripts/crewai-local-workflow.sh --goal "Subscriber growth plan"
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

## Troubleshooting

- `uv: command not found`
  - Install `uv`, then rerun `cd .crewai && uv sync`.
- `No LLM provider key found`
  - Add a provider key in `.crewai/.env` or run with `--dry-run`.
- `crewai run` fails
  - Use wrapper fallback:
    - `bash .claude/scripts/crewai-local-workflow.sh`
