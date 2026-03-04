# /ship - Fire and Forget Task Execution

The `/ship` command is the recommended way to execute tasks with guaranteed completion.

## Modes

### Multi-Session Ralph (Default for complex tasks)

For tasks with 3+ sub-tasks, `/ship` generates a PRD and launches an AFK Multi-Session Ralph loop. Each iteration runs in a fresh `claude -p` session — no context rot.

### Session Ralph (Fallback for simple tasks)

For quick 1-2 iteration tasks, `/ship` falls back to the in-session Ralph loop via `ralph_loop_hook.py`.

## What It Does

1. Analyzes the task complexity (simple vs complex)
2. **Complex path (3+ tasks):**
   a. Runs `promptsmith` to generate a PRD at `.claude/context/ralph-active/PRD.md`
   b. Breaks the task into ordered, atomic sub-tasks
   c. Launches `afk-ralph.sh` in the background (Docker if available)
   d. Returns immediately with status info
3. **Simple path (1-2 tasks):**
   a. Sets up Session Ralph loop (max 30 iterations, promise: TASK_COMPLETE)
   b. Executes the `autopilot` pipeline inline
   c. `closer` is the final gate — outputs completion promise

## Usage

```
/ship "Build a REST API for user management"
/ship "Fix all linting errors"
/ship "Add pagination to the /users endpoint"
```

## Architecture

### Multi-Session (Complex Tasks)

```
/ship "task"
+-- promptsmith (generates PRD)
+-- afk-ralph.sh (background loop)
    +-- ralph-once.sh (iteration 1) → fresh session
    +-- ralph-once.sh (iteration 2) → fresh session
    +-- ralph-once.sh (iteration N) → fresh session
    +-- <promise>COMPLETE</promise> → notify + exit
```

### Session (Simple Tasks)

```
Ralph Loop (wrapper, max 30 iterations)
+-- promptsmith (refines raw task)
+-- autopilot (implements + verifies)
|   +-- review-chain (review -> fix -> re-review, max 2 cycles)
|   |   +-- surgical-reviewer (structured FINDINGS_JSON output)
|   |   +-- autopilot-fixer (if blockers found)
|   +-- triage (if verification fails)
|   +-- autopilot-fixer (if issues remain)
+-- closer (final gate)
    +-- IF DoD met AND no blockers: <promise>TASK_COMPLETE</promise>
    +-- ELSE: loop continues
```

## Monitoring & Control

```
/ralph-status     # Check progress
/cancel-ralph     # Stop the loop
```

## When to Use

- Complex tasks requiring multiple iterations
- Tasks with verification requirements (tests must pass)
- Any task where you want guaranteed completion or timeout
- AFK execution (leave it running overnight)

## Context Checkpoints

Every 10 assistant responses, the `context_checkpoint` hook outputs a paste-ready continuation prompt to stderr. If you need to `/clear` mid-task, copy that block to resume seamlessly.

## Related Skills

- `/afk-ralph N "task"` — Explicit multi-session Ralph with custom iterations
- `/ralph-once` — Single iteration for human review
- `/ralph-status` — Check loop progress
- `/cancel-ralph` — Stop running loop

## Documentation

See `.claude/docs/ralph-pattern.md` for the full Ralph pattern reference, including PRD writing guide and troubleshooting.
