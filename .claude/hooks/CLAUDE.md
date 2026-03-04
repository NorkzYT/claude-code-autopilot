# Hooks Documentation

This directory contains hook implementations for Claude Code's event system.

## Hook Architecture

Hooks provide automated governance and safety controls:

```
User Prompt → PreToolUse → Tool Execution → PostToolUse → Response
                 ↓              ↓               ↓
              Block?        Monitor         Auto-format
```

## Available Hooks

### PreToolUse Hooks (Safety Valve)

| Hook | Matcher | Purpose |
|------|---------|---------|
| `protect_files.py` | Write, Edit, MultiEdit | Blocks edits to sensitive files (.env, secrets, certs) |
| `guard_bash.py` | Bash | Blocks dangerous commands (rm -rf, sudo, curl\|bash) |
| `log_bash.py` | Bash | Logs all bash commands for audit trail |

### PostToolUse Hooks (Auto-Chronicler)

| Hook | Matcher | Purpose |
|------|---------|---------|
| `format_if_configured.py` | Edit, MultiEdit, Write | Auto-formats edited files (Prettier/Black) |

### PostToolUseFailure Hooks

| Hook | Purpose |
|------|---------|
| `log_tool_failure.py` | Logs failed tool invocations for debugging |

### UserPromptSubmit Hooks (Context Injection)

| Hook | Purpose |
|------|---------|
| `log_prompt.py` | Logs user prompts for audit trail |
| `inject_context.py` | Dynamically injects relevant context based on prompt |

### Stop/SubagentStop Hooks (Session Cleanup)

| Hook | Purpose |
|------|---------|
| `log_assistant.py` | Logs assistant responses |
| `persist_session.py` | Saves session state to context directory |
| `ralph_loop_hook.py` | Ralph Wiggum iterative loop - blocks exit until completion promise fulfilled |

### Notification Hooks

| Hook | Purpose |
|------|---------|
| `notify_linux.py` | Desktop notifications when Claude needs attention |

## Hook Configuration

Hooks are configured in `.claude/settings.local.json`:

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit|MultiEdit",
        "hooks": [
          {
            "type": "command",
            "command": "python3 \"$CLAUDE_PROJECT_DIR/.claude/hooks/protect_files.py\"",
            "timeout": 3
          }
        ]
      }
    ]
  }
}
```

## Hook Return Codes

- **Exit 0**: Allow the operation to proceed
- **Exit 2**: Block the operation (PreToolUse only)
- Any stderr output is shown to the user

## Creating New Hooks

Hooks receive JSON input on stdin with:
```json
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "..."
  }
}
```

Example hook structure:

```python
#!/usr/bin/env python3
import json
import sys

data = json.load(sys.stdin)
tool_name = data.get("tool_name", "")
tool_input = data.get("tool_input", {})

# Your validation logic here

if should_block:
    print("BLOCKED: reason", file=sys.stderr)
    sys.exit(2)  # Exit 2 blocks the operation

sys.exit(0)  # Exit 0 allows the operation
```

## Sentinel Zone Integration

The `protect_files.py` hook enforces sentinel zones:
- Edit `PROTECTED_GLOBS` to add protected paths
- Edit `ALLOWED_PATTERNS` for safe exceptions
- Use `@sentinel` or `LEGACY_PROTECTED` comments in code for detection

## Environment Variables

| Variable | Purpose |
|----------|---------|
| `CLAUDE_PROJECT_DIR` | Root of the project being worked on |
| `CLAUDE_SESSION_ID` | Current session identifier |
| `CLAUDE_ALLOW_PROTECTED_EDITS` | Override to allow protected file edits |

## Extending Guard Bash

To allowlist specific packages in `guard_bash.py`:

```python
ALLOWLISTED_NPX = [
    r"^npx\s+prettier\b",
    r"^npx\s+eslint\b",
]
```

## Ralph Wiggum Iterative Loops

There are two Ralph modes. **Multi-Session Ralph** (external bash loop, fresh sessions) is the recommended default. **Session Ralph** (this hook) is useful for quick in-session iteration.

See `.claude/docs/ralph-pattern.md` for the full reference including decision matrix.

### Session Ralph (This Hook)

The `ralph_loop_hook.py` implements in-session iterative loops. It blocks session exit and re-injects the prompt for the next iteration within the **same session**. This is prone to context rot in long runs but is fast for quick 1-2 iteration fixes.

**How It Works:**
1. **Setup**: Use `/ralph-loop` command or `setup-ralph-loop.sh` script to create state file
2. **Iteration**: On each Stop event, the hook checks if the completion promise was fulfilled
3. **Continuation**: If not complete, blocks exit (exit code 2) and injects the prompt for next iteration
4. **Completion**: When `<promise>DONE</promise>` is output, loop ends and session exits normally
5. **Idle Detection**: If agent outputs 3 consecutive idle responses (e.g., ".", "Standing by"), loop auto-exits

**Commands:**
- `/ralph-loop [max_iter] [promise] "task"` - Start a session loop
- `/cancel-ralph` - Cancel any active loop

### Multi-Session Ralph (Recommended)

External bash scripts that run `claude -p` in a loop. Each iteration starts a **fresh session**, reads a PRD + progress file, completes ONE task, commits, and exits. No context rot.

**Commands:**
- `/ship "task"` - Fire-and-forget (generates PRD, launches loop)
- `/afk-ralph N "task"` - Explicit loop with N iterations
- `/ralph-once` - Single iteration for human review
- `/ralph-status` - Check loop progress
- `/cancel-ralph` - Stop any active loop

**Scripts:**
- `.claude/scripts/ralph-once.sh` - Single iteration
- `.claude/scripts/afk-ralph.sh` - Full AFK loop
- `.claude/scripts/ralph-docker.sh` - Docker sandbox wrapper

### Completion Promise Protocol

- Session Ralph: `<promise>TASK_COMPLETE</promise>` (or custom promise text)
- Multi-Session Ralph: `<promise>COMPLETE</promise>` in stdout
- The closer agent is the final gate for Session Ralph
