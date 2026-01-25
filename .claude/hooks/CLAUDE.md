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

## Ralph Wiggum Iterative Loop

The `ralph_loop_hook.py` implements iterative, self-referential development loops.

### How It Works

1. **Setup**: Use `/ralph-loop` command or `setup-ralph-loop.sh` script to create state file
2. **Iteration**: On each Stop event, the hook checks if the completion promise was fulfilled
3. **Continuation**: If not complete, blocks exit (exit code 2) and injects the prompt for next iteration
4. **Completion**: When `<promise>DONE</promise>` is output, loop ends and session exits normally

### State File Format

Location: `.claude/ralph-loop.local.md`

```markdown
---
active: true
iteration: 1
max_iterations: 20
completion_promise: "DONE"
started_at: "2024-01-01T00:00:00Z"
---

Your task prompt here
```

### Commands

- `/ralph-loop [max_iter] [promise] "task"` - Start a new loop
- `/cancel-ralph` - Cancel an active loop

### Integration with Autopilot Pipeline

The Ralph loop enhances the staged subagent pipeline by enabling:
- **Iterative refinement**: Keep working until tests pass
- **Self-healing**: Automatically retry failed tasks
- **Convergence loops**: Refine until quality gates pass

Example workflow:
```
/ralph-loop 10 TESTS_PASS "Implement feature X. Run tests after each change.
When all tests pass, output <promise>TESTS_PASS</promise>"
```

### Default Execution via /ship

The recommended way to execute tasks is via `/ship`, which sets up a Ralph loop with:
- `max_iterations: 30`
- `completion_promise: TASK_COMPLETE`

```
/ship "Build a REST API with tests"
```

This executes the full autopilot pipeline and loops until the closer agent outputs `<promise>TASK_COMPLETE</promise>`.

### Completion Promise Protocol

Agents in a Ralph loop should:
1. Check for `.claude/ralph-loop.local.md` at start
2. Output `<promise>PROMISE_TEXT</promise>` ONLY when truly done
3. The closer agent is the final gate that decides completion
