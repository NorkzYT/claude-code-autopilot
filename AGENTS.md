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
4. **Test** — Run test command from TOOLS.md
5. **Verify** — Browser-check if UI change (via CDP)
6. **Commit** — On feature branch, not main
7. **Report** — Summary of what changed, what was tested

Do not mark tasks complete after code-only changes.

## Shared Skills and Guardrails

- Skills source: `.claude/skills/` and generated `.openclaw/skills/`
- Codex repo skills path: `.agents/skills/` (symlink to `.openclaw/skills/`)
- Codex rule file: `.codex/rules/default.rules`
- Recommended local Codex state path: `.codex-home/` (via `ccx` alias)
- Codex compatibility templates: `.claude/templates/codex/`
- Safety hook references: `.claude/hooks/guard_bash.py`, `.claude/hooks/guard_browser.py`
