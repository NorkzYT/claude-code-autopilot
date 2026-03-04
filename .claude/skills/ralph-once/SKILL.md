# /ralph-once — Single Ralph Iteration (HITL Mode)

Run a single Multi-Session Ralph iteration for human review.
Reads the active PRD, completes ONE task, commits, and returns control to you.

## Usage

```
/ralph-once
/ralph-once .claude/context/my-feature/PRD.md
```

Arguments: `[prd_path]` (optional — defaults to `.claude/context/ralph-active/PRD.md` or `./PRD.md`)

## What It Does

1. Finds the active PRD (checks in order):
   - Argument path if provided
   - `.claude/context/ralph-active/PRD.md`
   - `./PRD.md`
2. Runs `.claude/scripts/ralph-once.sh` synchronously
3. Shows the iteration result
4. Returns control for human review

## Execution

When this skill is invoked:

1. Locate the PRD file (check paths in order above)
2. If no PRD found, ask the user to create one or use `/afk-ralph` to generate one
3. Run the iteration:
   ```bash
   .claude/scripts/ralph-once.sh "$(pwd)" "$PRD_PATH"
   ```
4. Read the updated progress.txt and report:
   - What task was completed
   - Files changed
   - Commit hash
   - What's next (or "PRD COMPLETE")
5. Wait for user to review before any further action

## HITL Workflow

```
You: /ralph-once          # Run one task
     <review changes>
You: /ralph-once          # Run next task
     <review changes>
You: /ralph-once          # Continue until done
```

This is the safest mode — you review each iteration before proceeding.
