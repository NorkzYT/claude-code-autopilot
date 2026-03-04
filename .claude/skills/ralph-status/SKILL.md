# /ralph-status — Show Ralph Loop Status

Display the current status of any active Ralph loop (both Session and Multi-Session).

## Usage

```
/ralph-status
```

## What It Does

Checks all Ralph state sources and reports a unified status.

## Execution

When this skill is invoked:

1. **Check Multi-Session Ralph**:
   - Read `.claude/context/ralph-active/progress.txt` if it exists
   - Check `.claude/context/ralph-active/pid` — is the process still running?
   - Count iterations completed (grep for `=== Iteration` lines)
   - Show last completed task and next task
   - Show elapsed time

2. **Check Session Ralph**:
   - Read `.claude/ralph-loop.local.md` if it exists
   - Parse frontmatter for active status, iteration count, max iterations
   - Show completion promise and current state

3. **Check logs**:
   - Tail last 5 lines of `.claude/logs/ralph-external.log`
   - Tail last 5 lines of `.claude/logs/ralph-loop.log`

4. **Report format**:
   ```
   Ralph Status
   ============

   Multi-Session Ralph: RUNNING
     PRD: .claude/context/ralph-active/PRD.md
     Progress: 3/8 tasks complete (iteration 4)
     Last task: Added user authentication middleware
     Next task: Create login endpoint
     PID: 12345 (running for 12m)

   Session Ralph: INACTIVE

   Recent log:
     [10:15:02Z] Iteration 4 complete — more work needed
     [10:12:30Z] Iteration 3 complete — more work needed
   ```

5. If nothing is active, report "No active Ralph loops" and suggest:
   - `/afk-ralph N "task"` to start a new loop
   - `/ralph-once` for single iteration
   - `/ship "task"` for fire-and-forget
