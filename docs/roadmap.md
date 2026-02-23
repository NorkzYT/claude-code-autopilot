# Roadmap: Full Engineer Workflow Kit

This roadmap tracks the move from a prompt-guided agent kit to a repeatable local engineering workflow system.

The target workflow is:

1. Fix
2. Build
3. Run local stack
4. Test
5. Confirm locally
6. Commit and report
7. Move to next bug

This means local developer workflows only. It does not mean staging or production deploys.

## Current State (Implemented)

- Claude Code hooks for safety, logging, and formatting (`.claude/hooks/*`)
- Staged agent workflow (autopilot, triage, fixer, closer)
- OpenClaw setup and agent bootstrap scripts
- OpenClaw Discord setup wizard with secure guild/channel/user allowlists
- OpenClaw browser Docker setup for CDP and local UI checks
- Generated `.openclaw/TOOLS.md` with detected build/test/local-run/confirm commands
- Sonnet-first routing and explicit Opus escalation path
- Commit trailer blocking (`Co-Authored-By`)

## Gaps (Not Fully Enforced Yet)

- Hard gate that requires build + local-run + test + confirm before "done"
- One stable remote command that always runs the full local workflow in the same order
- Structured evidence output (build log summary, test summary, smoke-check result)
- Policy that blocks PR creation when local verification steps are missing

## Next Steps (Recommended)

### 1) Add a local workflow wrapper command (highest impact)

Create one wrapper script that runs:

- build
- local run / restart
- tests
- confirm / smoke check
- summary report

Then route Discord or cron tasks through that wrapper for repeatable behavior.

See `docs/openclaw-plugin-hooks.md` and `docs/examples/openclaw-local-workflow-wrapper.sh`.

### 2) Add OpenClaw plugin hook checks

Use plugin hooks to:

- log command execution and outcomes
- inject workspace bootstrap files (`.openclaw/TOOLS.md`, `.openclaw/PROJECT.md`)
- store session memory for later review
- reject completion/reporting when required evidence is missing (custom plugin/wrapper)

### 3) Add a repo-level completion checklist format

Require a standard report with fields like:

- Build: pass/fail
- Local run: command used
- Test: pass/fail and counts
- Confirm: what was checked locally
- Files changed
- Next bug

### 4) Add per-repo command overrides

Keep `analyze_repo.sh` detection as the default and support project overrides in `.openclaw/TOOLS.md` where detection is not enough.

### 5) Add custom OpenClaw command wrappers (optional)

If you want stable remote commands in Discord (instead of free-form prompts), add custom wrappers like:

- `/localfix`
- `/verify-local`
- `/next-bug`

These should call the same local workflow wrapper script.

## Design Rules

- Prefer local commands (`yarn dev`, `make up`, `docker compose up`) over staging/prod actions
- Keep defaults safe (`commands.bash=false`, allowlists on Discord)
- Use slash commands first in Discord
- Keep automation idempotent and version-tolerant
- Treat `.openclaw/*` as the source of truth for generated workspace files
