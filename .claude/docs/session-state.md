# Session State Management (Three-File Pattern)

This document describes the externalized state pattern for session resilience.

## Problem

Context windows have limits. Long sessions accumulate cruft. Session interruptions lose progress.

## Solution: Three-File Pattern

Externalize session state to three files in `.claude/context/<task-name>/`:

### 1. plan.md (North Star)

High-level architectural plan that rarely changes:

```markdown
# Plan: <Task Name>

## Goal
One-sentence objective.

## Architecture Decision
Key technical approach chosen.

## Scope
- In scope: ...
- Out of scope: ...

## Milestones
1. [ ] Milestone 1
2. [ ] Milestone 2
3. [ ] Milestone 3

## Constraints
- Must use existing patterns
- No breaking changes to API
```

### 2. context.md (Scratchpad)

Living document of discoveries, decisions, and gotchas:

```markdown
# Context: <Task Name>

## Key Learnings
- File X uses pattern Y
- Config lives at Z

## Decisions Made
- Chose approach A over B because...
- Will defer X to follow-up

## Gotchas
- Watch out for circular import in module X
- Test Y is flaky, skip if needed

## File Map
- `src/core/handler.ts` - Main entry point
- `src/utils/validate.ts` - Validation helpers
```

### 3. tasks.md (Checklist)

Granular work items with status:

```markdown
# Tasks: <Task Name>

## Current Sprint
- [x] Read existing implementation
- [x] Identify files to modify
- [ ] Implement core change
- [ ] Add tests
- [ ] Run verification

## Blocked
- [ ] Waiting for API design review

## Deferred
- [ ] Performance optimization (follow-up)
```

## Document & Clear Cycle

Prevent context rot with periodic externalization:

1. **After major milestone**: Update all three files
2. **Before complex operation**: Persist current state
3. **On session pause**: Document progress and next steps
4. **On session resume**: Read three files to restore context

## Directory Structure

```
.claude/
└── context/
    ├── feature-auth/
    │   ├── plan.md
    │   ├── context.md
    │   └── tasks.md
    ├── bugfix-123/
    │   ├── plan.md
    │   ├── context.md
    │   └── tasks.md
    └── refactor-api/
        ├── plan.md
        ├── context.md
        └── tasks.md
```

## Automated Persistence

The `persist_session.py` hook (Stop event) can automatically:
1. Detect modified context files
2. Save session summary to context.md
3. Update tasks.md with completed items

## Usage Patterns

### Starting a New Task

```
1. Create context directory:
   mkdir -p .claude/context/<task-name>

2. Initialize plan.md with goal and scope

3. Let context.md and tasks.md evolve during work
```

### Resuming a Session

```
Read the three files in .claude/context/<task-name>/:
- plan.md for the big picture
- context.md for key learnings
- tasks.md for remaining work
```

### Complex Multi-Session Tasks

For tasks spanning multiple sessions:
1. Always update tasks.md before ending
2. Add "## Session N Summary" to context.md
3. Keep plan.md as the stable reference

## Context Store (Compound Intelligence)

Sub-agents report distilled context, not raw output:

```
Orchestrator
    ├── Spawns: explorer-1 → Returns: "Found 3 files using pattern X"
    ├── Spawns: explorer-2 → Returns: "Config uses env vars A, B, C"
    └── Spawns: coder → Returns: "Modified src/handler.ts, added validation"
```

Each sub-agent works with full context but reports only:
- Key findings (not exploration history)
- Decisions made (not alternatives considered)
- Verification results (pass/fail + summary)

This prevents context explosion in the parent orchestrator.

## Gitignore

Add to `.gitignore`:
```
.claude/context/
```

Session state is local working memory, not version-controlled artifacts.
