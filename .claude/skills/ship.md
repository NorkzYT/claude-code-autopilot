# /ship - Fire and Forget Task Execution

The `/ship` command is the recommended way to execute tasks with guaranteed completion.

## What It Does

1. Runs `promptsmith` to refine the raw task into an execution-ready prompt
2. Sets up a Ralph loop (max 30 iterations, promise: TASK_COMPLETE)
3. Executes the full `autopilot` pipeline (which includes `review-chain` for QA)
4. `closer` is the final gate -- verifies DoD and outputs completion promise
5. If closer says not done, the Ralph loop continues automatically

## Usage

```
/ship "Build a REST API for user management"
/ship "Fix all linting errors"
/ship "Add pagination to the /users endpoint"
```

## Architecture

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

## Pipeline Details

### promptsmith
Converts raw task text into a structured prompt with clear goal, constraints, and acceptance criteria.

### autopilot
Full delivery pipeline: plan -> implement -> self-verify -> review-chain -> fix -> close. See `.claude/agents/autopilot.md`.

### review-chain
Orchestrates up to 2 cycles of: surgical-reviewer -> parse findings -> autopilot-fixer (if blockers) -> re-review. Outputs a verdict: PASS, PASS_WITH_WARNINGS, or BLOCKERS_REMAIN.

### closer
Verifies DoD, checks review-chain verdict, runs final verification commands. Outputs `<promise>TASK_COMPLETE</promise>` only when everything passes.

## When to Use

- Complex tasks requiring multiple iterations
- Tasks with verification requirements (tests must pass)
- Any task where you want guaranteed completion or timeout

## Context Checkpoints

Every 10 assistant responses, the `context_checkpoint` hook outputs a paste-ready continuation prompt to stderr. If you need to `/clear` mid-task, copy that block to resume seamlessly.

## Cancellation

```
/cancel-ralph
```
