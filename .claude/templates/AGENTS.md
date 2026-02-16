# OpenClaw Agent Instructions

> Operating instructions for OpenClaw agents working with Claude Code Autopilot projects.

## Session State Pattern

All tasks use the **three-file pattern** for session persistence:

- `plan.md` -- High-level architectural plan (rarely changes)
- `context.md` -- Key learnings, decisions, gotchas (updated each session)
- `tasks.md` -- Granular checklist (updated frequently)

Store in `.claude/context/<task-name>/` directory.

## Dispatching Tasks to Claude Code

Use the `exec` tool to invoke Claude Code for terminal development tasks:

```
exec: claude --print "<task description>"
```

For complex tasks:
```
exec: claude --print "Use the autopilot subagent (Task tool with subagent_type=autopilot) for this task: <description>"
```

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

## Project Structure

```
.claude/
├── CLAUDE.md              # Constitution
├── agents/                # Agent definitions
├── hooks/                 # Safety hooks
├── commands/              # Workflows and tools
├── skills/                # Reusable knowledge
├── context/               # Session state
├── docs/                  # Reference docs
└── logs/                  # Audit trail
```
