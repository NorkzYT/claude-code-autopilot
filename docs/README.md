# Documentation

Use these docs when you need details that do not belong in the quick-start README.

## Guides

- `docs/install.md` — install modes, updates, installer flags, gitignore, `llms.txt`
- `docs/workflow.md` — session persistence, notifications, guardrails, customization, plan-mode workflow
- `docs/editor.md` — external editor (`Ctrl+G`) setup and VS Code remote notes
- `docs/troubleshooting.md` — common issues and validation commands
- `docs/openclaw.md` — OpenClaw setup summary and links to the full OpenClaw docs in `.claude/docs/`
- `docs/openclaw-plugin-hooks.md` — how to use OpenClaw hooks and wrapper commands for local workflow automation
- `docs/roadmap.md` — roadmap for full local engineer workflow enforcement

## OpenClaw Deep Docs (repo-local)

These are the OpenClaw-specific references used by the bootstrap scripts:

- `.claude/README-openclaw.md` — operator quick reference
- `.claude/docs/openclaw-integration.md` — full setup and operations guide
- `.claude/docs/openclaw-commands.md` — CLI and slash command reference
- `.claude/docs/openclaw-remote-commands.md` — Discord pairing, allowlists, bindings, slash commands

## Examples

- `docs/examples/openclaw-local-workflow-wrapper.sh` — sample local workflow wrapper (build → run-local → test → confirm)
- `docs/examples/openclaw-workflow-report-check.sh` — report checker for wrapper output
- `docs/examples/openclaw-workflow-enforcer-plugin/` — OpenClaw plugin hook skeleton (design example)
