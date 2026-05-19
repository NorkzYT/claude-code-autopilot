# Full Setup Guide: OpenClaw + Multi-Crew AI Workforce

> **This is the single entry-point guide.** Follow it top to bottom on a fresh dev machine. Subsections link to deeper references where needed.

## What You're Building

```
You (Discord)
     │
     ▼
OpenClaw Gateway (Docker, port 18789)
     │  Discord bot receives your message
     │
     ├─ Simple / immediate task ──────────────────────────────────────────────────────┐
     │    OpenClaw agent handles it inline (autopilot-workflow skill)                  │
     │    Coding → claude-max-proxy (port 3456) → Claude Code (Max subscription)       │
     │    Research/other → CrewAI crew (port 8317) → Codex (Codex subscription)        │
     │    Result posted back to Discord                                                │
     │                                                                                 │
     └─ Queue / multi-task run ──────────────────────────────────────────────────────┐ │
          Tasks written to bin/*.md (pending)                                         │ │
          engineering-loop.sh processes them one by one:                              │ │
            coding   → claude-max-proxy → Claude Code (tests, retry, commit)         │ │
            research → CrewAI ResearchCrew (Codex) → bin/outputs/<slug>/result.md   │ │
            creative → CrewAI CreativeCrew (Codex) → bin/outputs/<slug>/result.md   │ │
            <custom> → your private crew in .crewai/crews/private/                   │ │
                                                                                      ◄─┘
```

**Two subscription-backed engines, zero API costs:**
| Engine | Port | Subscription | Used for |
|--------|------|-------------|----------|
| claude-max-proxy | 3456 | Claude Max | Coding execution only |
| CLIProxyAPI | 8317 | OpenAI Codex / ChatGPT Plus | All thinking, planning, non-coding |

---

## Part 1 — Prerequisites Check

Before proceeding, verify all three services respond:

```bash
# 1. OpenClaw gateway
openclaw status

# 2. claude-max-proxy (Claude Max coding engine)
curl -s http://localhost:3456/health | python3 -m json.tool | head -5
# Expected: "loggedIn": true

# 3. CLIProxyAPI (Codex thinking engine)
curl -s http://127.0.0.1:8317/v1/models | python3 -m json.tool | head -10
# Expected: list of model entries including a Codex model
```

If any of these fail, fix them first:
- OpenClaw not responding → `make start` in `/opt/openclaw-home`
- claude-max-proxy not authenticated → see `docs/openclaw.md` § Claude Max Proxy Setup
- CLIProxyAPI not running → `make crewai-proxy-up` in this repo
- CLIProxyAPI logged out → see `docs/crewai.md` § CLIProxyAPI Setup

---

## Part 2 — Bootstrap the Multi-Crew Templates (One-time)

The multi-crew files (router, domain crews, CodeExecutorTool, private crew loader) were
added to the public templates but must be generated into your local `.crewai/`.
The bootstrap is safe to re-run — it skips files that already exist.

```bash
# From the repo root:
bash .claude/bootstrap/crewai_setup.sh /opt/repos/claude-code-autopilot

# You should see [SKIP] for existing files and ==> Created for:
#   src/<pkg>/router.py
#   src/<pkg>/tools/__init__.py
#   src/<pkg>/tools/code_executor.py
#   src/<pkg>/crews/__init__.py
#   src/<pkg>/crews/research.py
#   src/<pkg>/crews/creative.py
#   crews/private/README.md   (private crew instructions)

# Sync dependencies (no new deps, but confirms the env is clean)
cd .crewai && uv sync && cd ..
```

Verify the new files exist:

```bash
ls .crewai/src/*/crews/
ls .crewai/src/*/tools/
ls .crewai/crews/private/
```

---

## Part 3 — Wire Up the `.crewai/.env`

Your `.crewai/.env` needs entries for BOTH engines:

```bash
cd .crewai
# If you haven't already:
cp .env.example .env
```

Minimum required content in `.crewai/.env`:

```dotenv
# Codex engine (CLIProxyAPI) — thinking, planning, non-coding tasks
CREWAI_LLM_MODE=proxy
OPENAI_BASE_URL=http://127.0.0.1:8317/v1
OPENAI_API_BASE=http://127.0.0.1:8317/v1
CLI_PROXY_BASE_URL=http://127.0.0.1:8317/v1
CLI_PROXY_API_KEY=<key from .crewai/cliproxyapi/config.yaml>
OPENAI_API_KEY=<same key>
ENGINEERING_MODEL=gpt-5.3-codex

# Claude Max engine (claude-max-proxy) — coding execution only
CLAUDE_MAX_PROXY_URL=http://localhost:3456
ENGINEERING_CODE_MODEL=claude-sonnet-4-6
```

Get your proxy key:

```bash
grep -A5 'api-keys' .crewai/cliproxyapi/config.yaml
```

Smoke test the full chain:

```bash
cd .crewai
uv run python -m "$(cat .package-name)".main --type research --task "What is 2+2" --dry-run
# Should print: Dry run — inputs for router.dispatch(type='research')
```

---

## Part 4 — Discord as the Interface

### How it already works

OpenClaw's agent in your Discord channel handles tasks inline. When you send a message
to a channel bound to this repo, the agent:
1. Receives your message
2. Uses `autopilot-workflow` skill to plan and execute
3. For coding: calls claude-max-proxy directly (no API cost)
4. Reports completion back to Discord

**Nothing extra is needed for immediate single tasks.** Just send:

```
Add JWT authentication to the /opt/repos/myrepo API
```

The agent handles it end-to-end and reports back.

### Routing non-coding tasks from Discord

For research, creative writing, game design, chemistry, etc., ask the agent to use
the CrewAI crew. The agent can call it inline:

```
Research the best database for a real-time multiplayer game — give me a comparison table
```

Or explicitly route it:

```
Use the research crew to compare PostgreSQL vs MongoDB vs Redis for real-time leaderboards
```

The agent will call:
```bash
cd /opt/repos/claude-code-autopilot/.crewai && \
  uv run python -m <pkg>.main --type research --task "..."
```

And post the result back to Discord.

### Setting up the Discord channel → repo binding (if not done yet)

```bash
# 1. Register this repo as an OpenClaw agent (if not already)
make add-agent AGENT=autopilot REPO=/opt/repos/claude-code-autopilot

# 2. Configure Discord (bot token, guild, channel)
bash .claude/bootstrap/openclaw_discord_setup.sh

# 3. Bind the channel to this repo agent with concurrency settings
bash .claude/bootstrap/openclaw_discord_scale_setup.sh
```

In Discord:
```
/new          ← start a fresh session on this repo agent
/status       ← confirm: Session: agent:autopilot:discord:channel:<id>
```

---

## Part 5 — Batch Task Queue (Engineering Loop)

For running multiple tasks hands-free (while you're away from the computer):

### Step 1 — Create a task file

```bash
cat > /opt/repos/claude-code-autopilot/bin/my-tasks.md << 'EOF'
# Tasks

## Task: add-error-handling
**Status:** pending
**Type:** coding
**Branch:** feat/add-error-handling

Add proper error handling to the API. All endpoints should return structured
JSON errors with a `code` field and `message` field. HTTP 400 for validation
errors, 500 for internal errors. Add tests.

---

## Task: research-caching-strategy
**Status:** pending
**Type:** research

Research Redis vs Memcached vs in-process caching for a high-read API. Include:
latency benchmarks, cost comparison, operational complexity, and a recommendation
for a team of 3 engineers.

---
EOF
```

### Step 2 — Dry-run to verify parsing

```bash
bash .claude/scripts/engineering-loop.sh --dry-run bin/my-tasks.md
```

Expected output shows both tasks with correct types and slugs.

### Step 3 — Run

```bash
# From terminal (direct)
bash .claude/scripts/engineering-loop.sh bin/my-tasks.md

# With CrewAI-generated PRD for coding tasks
bash .claude/scripts/engineering-loop.sh --use-planner bin/my-tasks.md

# All *.md files in bin/ at once
bash .claude/scripts/engineering-loop.sh bin/
```

### Step 4 — Check results

- **Coding tasks:** committed to the branch specified in `**Branch:**`
- **Non-coding tasks:** output written to `bin/outputs/<slug>/result.md`
- **Log:** `.claude/logs/engineering-loop.log`

### Running the loop from Discord (on-demand)

In your Discord channel, ask the OpenClaw agent:

```
Run the engineering loop on bin/ in /opt/repos/claude-code-autopilot
```

Or set up an OpenClaw cron to run it automatically:

```bash
# Add a host-side cron that runs every 30 minutes
# (OpenClaw cron runs inside Docker; for host-side scripts use system crontab)
crontab -e
# Add:
# */30 * * * * bash /opt/repos/claude-code-autopilot/.claude/scripts/engineering-loop.sh /opt/repos/claude-code-autopilot/bin >> /opt/repos/claude-code-autopilot/.claude/logs/cron-loop.log 2>&1
```

---

## Part 6 — Adding Private Crews

Your private crews live in `.crewai/crews/private/` — this directory is
gitignored. **Nothing you put here is ever committed.**

### Create a private crew

```python
# .crewai/crews/private/game_design.py

CREW_NAME = "game-design"   # the routing key

def run(task_description: str, **kwargs) -> str:
    import os
    from crewai import Agent, Crew, LLM, Process, Task

    llm = LLM(
        model=os.getenv("ENGINEERING_MODEL", "gpt-5.3-codex"),
        base_url=os.getenv("OPENAI_BASE_URL", "http://127.0.0.1:8317/v1"),
        api_key=os.getenv("OPENAI_API_KEY", ""),
    )

    designer = Agent(
        role="Game Designer",
        goal="Design engaging, balanced, and fun game mechanics and systems.",
        backstory=(
            "You are a veteran game designer with expertise in game loops, "
            "economy design, player psychology, and mechanics balance."
        ),
        llm=llm,
        verbose=True,
    )
    task = Task(
        description=task_description,
        agent=designer,
        expected_output=(
            "A detailed game design document with mechanics, progression systems, "
            "and implementation notes."
        ),
    )
    crew = Crew(agents=[designer], tasks=[task], process=Process.sequential)
    return str(crew.kickoff())
```

### Use it in a task file

```markdown
## Task: design-combat-system
**Status:** pending
**Type:** game-design

Design a turn-based combat system for a roguelike game. Include:
- Action economy (AP system vs cooldowns)
- Status effect framework
- Enemy AI archetypes
- Balancing levers for difficulty scaling
```

### Use it from Discord

```
Design a crafting system for my roguelike game using the game-design crew
```

The loader auto-discovers any `.py` file in `.crewai/crews/private/` that
has a `run()` function. No registration needed.

---

## Part 7 — Reference: Task Type Routing

| `**Type:**` value | Engine | Behaviour |
|-------------------|--------|-----------|
| `coding` (default) | claude-max-proxy → Claude Code | Branch checkout, tests run, retried on failure, committed |
| `research` | CLIProxyAPI → ResearchCrew (Codex) | Output → `bin/outputs/<slug>/result.md` |
| `creative` | CLIProxyAPI → CreativeCrew (Codex) | Output → `bin/outputs/<slug>/result.md` |
| `auto` | Codex classifies → dispatches | Whichever crew Codex thinks fits |
| `<custom>` | CLIProxyAPI → private crew matching `CREW_NAME` | Output → `bin/outputs/<slug>/result.md` |

---

## Part 8 — Troubleshooting

| Symptom | Fix |
|---------|-----|
| `No module named <pkg>.router` | Re-run bootstrap: `bash .claude/bootstrap/crewai_setup.sh` |
| `uv: command not found` in loop | Install uv on host: `curl -LsSf https://astral.sh/uv/install.sh \| sh` |
| Engineering loop: `planner: .crewai not found` | Drop `--use-planner` or run bootstrap first |
| Crew task fails silently | Check `.claude/logs/engineering-loop.log` |
| CLIProxyAPI returns 401 | Re-run Codex device login: `docker exec -it cliproxyapi-<slug> ./CLIProxyAPI -config /app/config.yaml -codex-device-login` |
| claude-max-proxy returns 401 | Re-run `docker exec -it claude-max-proxy claude setup-token` in `/opt/openclaw-home` |
| Discord not responding | `openclaw channels status` → `make restart` in `/opt/openclaw-home` |
| Wrong agent in Discord | `bash .claude/bootstrap/openclaw_discord_scale_setup.sh` to rebind channel |

---

## Quick-Reference: Daily Commands

```bash
# Check everything is alive
openclaw status
curl -s http://localhost:3456/health | python3 -c "import sys,json; d=json.load(sys.stdin); print('claude-max-proxy:', d.get('auth', {}).get('loggedIn'))"

# Add a task and run immediately
echo "..." >> bin/tasks.md   # edit the file to add a pending task
bash .claude/scripts/engineering-loop.sh --dry-run bin/tasks.md   # verify
bash .claude/scripts/engineering-loop.sh bin/tasks.md             # run

# Tail the loop log
tail -f .claude/logs/engineering-loop.log

# Restart all Docker services if needed
make stop && make start   # in /opt/openclaw-home
make crewai-proxy-up      # in this repo (if Codex proxy stopped)
```

---

## Deep-Dive References

| Topic | File |
|-------|------|
| OpenClaw full setup | `docs/openclaw.md` |
| CrewAI crews + CLIProxyAPI | `docs/crewai.md` |
| Engineering loop options | `docs/crewai.md` § Running the Engineering Loop |
| Private crews interface | `.crewai/crews/private/README.md` |
| Docker stack details | `docs/docker-openclaw-crewai.md` |
| Discord remote commands | `.claude/docs/openclaw-remote-commands.md` |
| Adding private crews | `docs/crewai.md` § Adding Private Crews |
