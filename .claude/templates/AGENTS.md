# OpenClaw Agent Instructions

> Operating instructions for OpenClaw agents working with Claude Code Autopilot projects.

## Session State Pattern

All tasks use the **three-file pattern** for session persistence:

- `plan.md` -- High-level architectural plan (rarely changes)
- `context.md` -- Key learnings, decisions, gotchas (updated each session)
- `tasks.md` -- Granular checklist (updated frequently)

Store in `.claude/context/<task-name>/` directory.

## Dispatching Tasks to Claude Code

Most tasks should be handled directly by the current model. Only escalate to Claude Code for complex multi-file architectural changes.

### Direct execution (default -- saves tokens):
Handle the task yourself using the available tools. Follow the Task Completion Protocol.

### Model Routing (Quality + Cost)

- Start on **Sonnet** for plan/triage and most implementation.
- Route automatically by complexity; do not ask the user which model to use unless they explicitly request one.
- After the plan is clear, escalate to **Opus/autopilot-opus** automatically only for complex multi-file or architectural work.
- Keep browser/HAR/vision steps explicit and only when required.

### Claude Code escalation (complex tasks only):
For multi-component architectural changes that need specialist sub-agents:
```
exec: claude --print "Use the autopilot-opus subagent (Task tool with subagent_type=autopilot-opus) for this task: <description>"
```

**Escalation criteria:** 4+ files across modules, architectural decisions, high regression risk, or 3+ distinct deliverables.

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
