# AGENTS.md - Codex Compatibility for Claude Code Autopilot

This repository is OpenClaw-first, but supports OpenAI Codex workflows.

## Primary Policy Files

Read and follow these files in order:

1. `.claude/CLAUDE.md`
2. `.claude/templates/AGENTS.md`
3. `.claude/templates/agent-persona/AGENTS.md.tmpl`

## Task Completion Protocol

For EVERY bug fix or feature:
1. **Understand** — Read PROJECT.md, relevant source files
2. **Fix** — Make the code change
3. **Build** — Run build command from TOOLS.md
4. **Run Local** — Start or reload the local stack only (e.g. `yarn dev`, `make up`, `docker compose up`)
5. **Test** — Run test command from TOOLS.md
6. **Confirm** — Verify the changed flow works locally (browser-check if UI change via CDP)
7. **Commit** — On feature branch, not main
8. **Report** — Summary of what changed, what was tested

Do not mark tasks complete after code-only changes.

## Timed Follow-Ups (OpenClaw)

- Never say "I will check back in X minutes/hours" unless you create a real OpenClaw cron job first.
- Use `/recheckin <delay> <task>` in Discord/OpenClaw channels to make timed follow-ups real.
- When a timed follow-up is scheduled, include the cron `jobId` (or say the CLI did not return one) in the reply.
- If scheduling fails, do not promise a timed callback. Ask the user to ping you later or keep monitoring synchronously.
- Strong rule: timed promise language is forbidden unless `/recheckin` succeeded in the same turn.
- Forbidden without cron success: "I'll check back in X", "give me X minutes and I'll re-check", "I'll report back in X".

## Cost-Optimized Routing

- Claude/OpenClaw: use Sonnet first for plan + direct execution.
- Escalate to Opus/autopilot only for complex multi-file/architectural tasks.
- Codex: follow the same plan-first/direct-first policy and keep browser verification explicit.

## Shared Skills and Guardrails

- Skills source: `.claude/skills/` and generated `.openclaw/skills/`
- Codex repo skills path: `.agents/skills/` (symlink to `.openclaw/skills/`)
- Codex rule file: `.codex/rules/default.rules`
- Recommended local Codex state path: `.codex-home/` (via `ccx` alias)
- Codex compatibility templates: `.claude/templates/codex/`
- Safety hook references: `.claude/hooks/guard_bash.py`, `.claude/hooks/guard_browser.py`
- Commit trailer enforcement: generated `.git/hooks/commit-msg` blocks `Co-Authored-By`
