# /cancel-ralph — Cancel Active Ralph Loop

Stop any running Ralph loop (both Session and Multi-Session).

## Usage

```
/cancel-ralph
```

## What It Does

Safely stops all active Ralph loops and preserves progress.

## Execution

When this skill is invoked:

1. **Cancel Multi-Session Ralph**:
   - Check `.claude/context/ralph-active/pid`
   - If PID file exists and process is running:
     - Send SIGTERM to the process
     - Wait up to 5 seconds for clean shutdown
     - Append cancellation note to progress.txt
   - If Docker container is running (derive project name from workspace hash):
     ```bash
     WORKSPACE_HASH=$(echo -n "$(pwd)" | md5sum | cut -c1-8)
     RALPH_PROJECT_NAME="ralph-${WORKSPACE_HASH}" \
       docker compose -f docker-compose.ralph.yml -p "ralph-${WORKSPACE_HASH}" stop
     ```
   - Report: "Multi-Session Ralph stopped at iteration N"

2. **Cancel Session Ralph**:
   - Run the existing cancel script:
     ```bash
     bash .claude/scripts/cancel-ralph-loop.sh
     ```
   - Report: "Session Ralph deactivated"

3. **Clean up**:
   - Do NOT delete progress.txt or PRD.md (preserve work)
   - Remove PID file

4. **Report**:
   ```
   Ralph loop cancelled.
     Progress preserved: .claude/context/ralph-active/progress.txt
     Completed: 5/8 tasks
     To resume: /afk-ralph --prd .claude/context/ralph-active/PRD.md
   ```

5. If nothing was running:
   ```
   No active Ralph loops found.
   ```
