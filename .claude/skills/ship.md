# /ship - Fire and Forget Task Execution

The `/ship` command is the recommended way to execute tasks with guaranteed completion.

## What It Does

1. Sets up a Ralph loop (max 30 iterations, promise: TASK_COMPLETE)
2. Executes the full autopilot pipeline
3. Loops until the closer agent confirms DoD is met
4. Outputs `<promise>TASK_COMPLETE</promise>` when done

## Usage

```
/ship "Build a REST API for user management"
/ship "Fix all linting errors"
/ship "Add pagination to the /users endpoint"
```

## Architecture

```
Ralph Loop (wrapper)
+-- promptsmith (refines)
+-- autopilot (implements)
|   +-- triage (if issues)
|   +-- fixer (if needed)
+-- closer (verifies)
    +-- IF done: <promise>TASK_COMPLETE</promise>
    +-- ELSE: loop continues
```

## When to Use

- Complex tasks requiring multiple iterations
- Tasks with verification requirements (tests must pass)
- Any task where you want guaranteed completion or timeout

## Cancellation

```
/cancel-ralph
```
