# CrewAI Setup and Workflow

This guide explains how to use the CrewAI integration added by `--with-crewai`.
The scaffold ships a generic two-agent engineering planner crew that turns a
single task description into a reviewed, executable implementation plan.

## What `--with-crewai` Adds

- Runs `.claude/bootstrap/crewai_setup.sh`
- Scaffolds `.crewai/` with:
  - Engineering planner agents and tasks config
  - Python entrypoint (`--task` / `--context-files`)
- Adds host-side runners:
  - `.claude/scripts/crewai-local-workflow.sh` (planner wrapper)
  - `.claude/scripts/engineering-loop.sh` (autonomous task driver)

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

Plan a single task and print the result to stdout:

```bash
cd .crewai
uv run python -m <package>.main --task "Add JWT auth to the API"
```

The exact `<package>` name is written to `.crewai/.package-name` (slug-derived,
e.g. `myrepo_crew`). Or use the host wrapper:

```bash
make crewai-workflow GOAL="Add JWT auth to the API"
# Or directly:
bash .claude/scripts/crewai-local-workflow.sh --task "Add JWT auth to the API"
```

Auto-start the local CLIProxyAPI for subscription-backed routing:

```bash
bash .claude/scripts/crewai-local-workflow.sh --with-proxy --task "Add JWT auth"
```

Dry-run without calling an LLM (echoes the assembled inputs):

```bash
bash .claude/scripts/crewai-local-workflow.sh --dry-run
```

## Default Engineering Crew

The scaffold defines two sequential agents:

- `task_planner` — drafts an atomic, testable implementation plan.
- `plan_reviewer` — reviews the plan, tightens ambiguity, then emits the final
  markdown ready to hand to Claude Code.

The pipeline runs two sequential tasks (`plan_task` -> `review_task`) and
returns the reviewer's output as the crew result.

## Engineering Planner Mode

When you pair the crew with the autonomous driver, the planner produces a PRD
that the driver feeds into `claude -p`:

```bash
bash .claude/scripts/engineering-loop.sh --use-planner bin/tasks.md
```

The driver runs the planner once per pending task and writes the result to
`.claude/context/engineering-loop/<task-slug>/PRD.md`. If `.crewai/` or `uv`
is missing the driver logs a warning and proceeds without a PRD (the task
description alone is still passed to Claude).

## Task File Format

The driver reads a markdown file shaped like `bin/tasks.example.md`:

```markdown
# Tasks

## Task: add-jwt-auth
**Status:** pending
**Branch:** feat/add-jwt-auth

<free-form task description here, including acceptance criteria>

---
```

- Headers must start with `## Task: <slug>`.
- `**Status:**` values: `pending` | `in-progress` | `done` | `failed`.
- `**Branch:**` is optional. Default is `feat/<slug>`.
- Everything after the metadata block (and before the `---` separator) is the
  task description.
- The driver only processes `pending` tasks. It updates statuses in place to
  `in-progress`, then `done` or `failed`.

## Running the Engineering Loop

```bash
# Show the loop's --help
bash .claude/scripts/engineering-loop.sh --help

# Dry-run (parse and print only — no execution)
bash .claude/scripts/engineering-loop.sh --dry-run bin/tasks.example.md

# Live run, no planner, retry tests up to 3 times on failure
bash .claude/scripts/engineering-loop.sh bin/tasks.md

# Live run with planner-generated PRDs and a 5-retry budget
bash .claude/scripts/engineering-loop.sh \
  --use-planner --max-retries 5 bin/tasks.md

# Override the workspace
bash .claude/scripts/engineering-loop.sh \
  --workspace /opt/repos/myrepo bin/tasks.md
```

Per task, the driver:

1. Marks the task `in-progress` in the tasks file.
2. Checks out `**Branch:**` (creating it if missing).
3. If `--use-planner`, runs the CrewAI planner crew to generate a PRD.
4. Launches `claude --permission-mode acceptEdits -p "<prompt>"` with the task
   description, optional PRD, branch, and detected test command.
5. Detects a test command (`make test`, `npm test`, `pytest`, `cargo test`,
   `go test ./...`) and runs it after the session.
6. On test failure, retries `--max-retries` times with the previous test output
   attached as context.
7. Marks the task `done` (tests pass / agent completed) or `failed` (retries
   exhausted or agent emitted `<promise>FAILED: ...</promise>`).

Make-target shortcuts:

```bash
make engineering-loop ARGS="--use-planner bin/tasks.md"
make engineering-loop-dry TASKS_FILE=bin/tasks.example.md
```

## CLIProxyAPI Mode (Subscription-Backed)

If you want CrewAI to route through a local OpenAI-compatible proxy instead of
direct provider API keys:

### Step 1 — Start the proxy container

```bash
make crewai-proxy-up
# or: bash .claude/scripts/crewai-cliproxyapi.sh up
```

### Step 2 — Log in to your Codex subscription (one-time)

CLIProxyAPI v7+ ships two Codex auth flows. Pick one:

**OAuth (recommended — requires a browser on the same machine):**

```bash
docker exec -it cliproxyapi ./CLIProxyAPI -config /app/config.yaml -codex-login
```

Opens a browser tab to accounts.openai.com. Sign in with the ChatGPT account that
holds your Plus, Pro, Business, or Enterprise plan. The callback lands on
`localhost:1455` or `localhost:54545` (both are mapped in the compose file).

**Device code (headless / no local browser):**

```bash
docker exec -it cliproxyapi ./CLIProxyAPI -config /app/config.yaml -codex-device-login
```

Prints a short code and a URL you open on any device. No callback redirect needed.

Both flows write OAuth state to the `auths/` volume (`./tmp/cliproxyapi/auths` on host
by default). The running server picks it up immediately and auth survives container restarts.

Verify the login worked:

```bash
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
ENGINEERING_MODEL=gpt-5.3-codex
```

`ENGINEERING_MODEL` must match a model name returned by `/v1/models`.
After login the proxy exposes whatever Codex reports — check the `curl` output above.

### Step 4 — Run CrewAI

```bash
bash .claude/scripts/crewai-local-workflow.sh --with-proxy --task "Add JWT auth"
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
docker exec -it crewai-runner crewai-entrypoint run /opt/repos/<repo-name> \
  --task "Add JWT auth to the API"
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
- Engineering loop reports `planner: .crewai not found`
  - Either drop `--use-planner` or run `bash .claude/bootstrap/crewai_setup.sh` first.
