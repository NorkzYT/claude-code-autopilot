# OpenClaw Agent Instructions

> Operating instructions for OpenClaw agents working with Claude Code Autopilot projects.

## Session State Pattern

All tasks use the **three-file pattern** for session persistence:

- `plan.md` -- High-level architectural plan (rarely changes)
- `context.md` -- Key learnings, decisions, gotchas (updated each session)
- `tasks.md` -- Granular checklist (updated frequently)

Store in `.claude/context/<task-name>/` directory.

## Autopilot Workflow (Mandatory for All Coding Tasks)

**YOUR FIRST LINE FOR ANY CODING TASK MUST BE:**
```
**Triage:** Simple/Medium/Complex, <file count> files -- <brief description>
```

**Then output each subsequent step header before executing it:**
- **Plan:** <numbered list>
- **Implement:** <as you code>
- **Verify:** <build/test results>
- **Commit:** <commit hash>
- **Report:** <summary>

**IMPORTANT: This is NOT optional guidance. You MUST output these headers. Follow this pipeline automatically for EVERY coding task. Do not wait for the user to ask.**

### Step 1: Triage
- Classify: **Simple** (1-2 files) / **Medium** (3-4 files) / **Complex** (4+ files, architectural)
- Complex tasks → escalate to Opus via `autopilot-opus` subagent
- For tasks expected to take >5 min: create `/recheckin` cron FIRST, include job ID in message

### Step 2: Plan
- Write a short plan (3-10 lines) before implementing
- Identify files to change, dependencies, and risk areas

### Step 3: Implement
- Read before writing. Follow existing patterns. Smallest change possible.
- Quality: SOLID, DRY, KISS, Separation of Concerns
- For each edit: Reason → Act → Observe (re-read file after editing) → Repeat if mismatch

### Step 4: Verify
- Re-read EVERY changed file after editing
- Run build command from TOOLS.md
- Run test command from TOOLS.md
- 4+ files changed → run self-review checklist (missed edge cases, naming, error handling)

### Step 5: Commit
- Conventional format: `type(scope): description`
- Feature branch only. Never commit untested code.
- NEVER include `Co-Authored-By` in commit messages.

### Step 6: Report
- What changed (bullets), files modified, test results, status

### Session Health
- After 20-25 coding turns: write checkpoint to `memory/YYYY-MM-DD.md`, suggest `/new`
- `/recheckin` enforcement: for any task >5 min, create cron job BEFORE starting. Include job ID or state CLI did not return one.

For detailed reference, read the skill files: `autopilot-workflow`, `quality-gates`, `model-router`, `session-hygiene`

## Coding Standards

1. **Smallest change** -- No drive-by refactors
2. **Discovery first** -- Search/read before deciding
3. **Follow existing patterns** -- Match repo style, naming, structure
4. **Always verify** -- Run tests/lint/build after changes
5. **No destructive commands** -- Unless explicitly approved

## Memory

Write durable insights to `MEMORY.md` in the OpenClaw workspace:
- Project architecture overview
- Key decisions and rationale
- Common patterns and conventions
- Critical file paths and purposes
- Known gotchas and workarounds

## Safety Rules

- Never modify `.env` files, secrets, or certificates without approval
- Never run destructive file removal commands
- Always run tests after code changes
- Report failures to Discord channel immediately
- Never include `Co-Authored-By` in commit messages (enforced by git `commit-msg` hook in generated workspaces)

## Project Structure

```
.claude/
├── CLAUDE.md              # Constitution
├── agents/                # Agent definitions
├── hooks/                 # Safety hooks
├── commands/              # Workflows and tools
├── skills/                # Reusable knowledge
├── templates/codex/       # Codex compatibility templates
├── context/               # Session state
├── docs/                  # Reference docs
└── logs/                  # Audit trail
```

## Autonomous Task Execution

### Prerequisites

- `OPENCLAW_AUTONOMOUS=1` environment variable must be set
- Only cron jobs or explicit automation wrappers should set this variable
- Interactive sessions always run in supervised mode

### Long-Running Task Pattern

1. **Accept task** — Receive task from Discord, cron, or CLI
2. **Create branch** — Use a professional feature branch (for example `fix/<task-name>` or `feat/<task-name>`)
3. **Create session state** — Write plan.md, context.md, tasks.md
4. **Execute in Ralph loop** — Use autopilot pipeline with completion promise
5. **Build** — Run the project build command from TOOLS.md
6. **Run local stack** — Start or reload the app/services locally (for example `yarn dev`, `make up`, `docker compose up`)
7. **Run tests** — Verify all changes pass
8. **Confirm locally** — Smoke-check the changed flow (browser/CDP for UI changes)
9. **Commit changes** — Conventional commit messages only (commits must appear as the user's own)
10. **Push branch** — Push the feature branch to origin before creating a PR
11. **Report via Discord** — Summary, changes, test results, remaining work
12. **Persist state** — Save session state for future reference

### Timed Follow-Up Promise Rule

- Never promise a timed follow-up ("I'll check back in 5 minutes") unless a real OpenClaw cron job is created first.
- In Discord/OpenClaw channels, create the follow-up with `/recheckin <delay> <task>`.
- Return the cron job ID (or clearly state if the CLI did not return one) so the promise is auditable.
- If scheduling fails, do not make the timed promise. Ask the user to ping again or keep monitoring now.
- Strong rule: timed promise language is forbidden unless `/recheckin` succeeded in the same turn and the reply includes the cron job ID (or says the CLI did not return one).
- Forbidden without cron success: "I'll check back in X", "let me re-check in X", "I'll report back in X".

### Cron Job Rules for Non-Default Agents

Non-default agents (any agent that is not `main`) **cannot** use `--session main`. OpenClaw enforces `--session isolated` for all non-default agents. Isolated cron sessions have NO Discord context (no guild ID, no channel history). Rules:

1. **Never reference Discord channels by name** in cron prompts (e.g., "post to #milestone-2"). The `message` tool cannot resolve names — only `channel:<numericId>`.
2. **Use `--to "channel:<ID>"` for delivery** — pass the thread/channel numeric ID. The `announce` delivery handles routing.
3. **Keep cron prompts task-focused** — describe WHAT to do, not WHERE to post.
4. **Always use `--session isolated`** for non-default agents (it's the only option).

Correct: `openclaw cron add --agent myagent --session isolated --announce --to "channel:1234567890" --message "Summarize progress."`
Wrong: `--session main --agent myagent` (ERROR), `--message "Post to #channel-name"` (FAIL: can't resolve names)

### Error Recovery

- **Session expiry** → Re-authenticate via cookie import
- **Test failure** → Triage with debugger agent, retry max 3 times
- **Network error** → Wait 30 seconds, retry max 3 times
- **Git conflict** → Report to Discord, do not force resolve

### Git Commit Policy (Autonomous Mode)

- **Branch naming:** Use professional names like `fix/<short-description>`, `feat/<short-description>`, or `chore/<short-description>`
- **NEVER** commit directly to main or master
- **NEVER** include `Co-Authored-By` lines in commit messages -- commits must appear as the user's own
- **NEVER** use `--author` flag to override commit author
- **NEVER** use `--amend` in autonomous mode
- **NEVER** force push (`--force` or `-f`)
- **Commit format:** Conventional commits (`feat:`, `fix:`, `chore:`, `docs:`)
- After all work is complete, push the branch to `origin` and create a PR for user review

### Reporting Template

```
## Autonomous Task Report
- **Task:** <description>
- **Branch:** feat/<name> (or fix/<name>, chore/<name>)
- **Status:** Complete / Partial / Failed
- **Changes:** <file count> files modified
- **Tests:** <pass>/<total> passing
- **Commits:** <count> commits
- **Remaining:** <any unfinished work>
```

## Data Verification Pattern

For comparing scraped data against live website data:

1. **Load scraped data** — Read from local DB/files
2. **Launch browser** — `openclaw browser launch`
3. **Authenticate** — Import cookies for target site (see LOGIN_PATTERNS.md)
4. **Navigate to data pages** — Go to product/listing pages
5. **Extract live data** — Snapshot page, extract values via AI vision
6. **Compare** — Diff scraped vs live data, log discrepancies
7. **Fix scraping code** — If logic is wrong, fix the scraper
8. **Run tests** — Verify scraping tests pass
9. **Commit fix** — On feature branch, conventional format
10. **Report via Discord** — Discrepancy count, fixes applied, confidence level

## API Reverse Engineering Pattern

1. **Start HAR capture** — `openclaw browser har start`
2. **Navigate workflows** — Visit target site pages that trigger API calls
3. **Stop capture** — `openclaw browser har stop`
4. **Analyze HAR** — Extract endpoints, auth headers, pagination patterns
5. **Document findings** — Write to context.md
6. **Generate API client** — Create typed client code for discovered endpoints
7. **Test read-only** — Verify GET requests against live API return expected data
8. **NEVER** send POST/PUT/DELETE to external APIs without explicit approval

## Browser Automation Rules

- **Always** import cookies before accessing authenticated pages
- **Always** take screenshots before AND after interactions (audit trail)
- **Never** modify live data on external sites (read-only only)
- **Rate-limit:** Wait 2-5 seconds between page navigations
- **Headless mode** by default unless debugging or testing extensions
- **Re-snapshot** after every navigation (element refs become stale)
- **Timeout:** 30 seconds per page load, abort and report if exceeded
