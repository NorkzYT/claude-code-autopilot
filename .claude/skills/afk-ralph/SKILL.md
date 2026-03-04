# /afk-ralph — Multi-Session AFK Ralph Loop

Launch an AFK Ralph loop that runs `claude -p` in fresh sessions per iteration.
Each iteration reads a PRD, completes ONE task, commits, and exits. No context rot.

## Usage

```
/afk-ralph 20 "Build REST API with auth"
/afk-ralph 10 "Refactor database layer"
```

Arguments: `[iterations] "task description"`

## What It Does

1. **Generate PRD**: Creates a PRD.md from the task description using promptsmith
2. **Create progress.txt**: Initializes empty progress tracker
3. **Launch loop**: Starts `afk-ralph.sh` in the background
4. **Notify on completion**: Desktop/push notification when done

## Execution

When this skill is invoked:

1. Parse the arguments — extract iteration count (default 20) and task description
2. Generate a PRD from the task description. Write it to `.claude/context/ralph-active/PRD.md`:
   - Use the PRD template from `.claude/templates/PRD-template.md`
   - Break the task into 3-8 ordered, atomic sub-tasks
   - Include validation commands
3. Create `.claude/context/ralph-active/progress.txt` with initial header
4. Check if Docker is available:
   - If yes: use `--docker` flag
   - If no: run directly
5. Launch the loop:
   ```bash
   nohup .claude/scripts/afk-ralph.sh \
     --iterations $N \
     --prd .claude/context/ralph-active/PRD.md \
     --workspace "$(pwd)" \
     > .claude/logs/ralph-external.log 2>&1 &
   ```
6. Save the PID to `.claude/context/ralph-active/pid`
7. Report to user:
   - PRD location
   - Progress file location
   - PID for monitoring
   - How to check status: `/ralph-status`
   - How to cancel: `/cancel-ralph`

## Notes

- The loop runs in the background — you can continue working
- Each iteration starts a fresh Claude session (no context rot)
- Monitor with `/ralph-status`, cancel with `/cancel-ralph`
- Logs at `.claude/logs/ralph-external.log`
- For single iteration (HITL mode), use `/ralph-once` instead
