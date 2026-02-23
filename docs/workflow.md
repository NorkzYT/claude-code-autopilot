# Workflow and Guardrails

This page covers how the kit is meant to be used day to day.

## Session Persistence (Three-File Pattern)

Use `.claude/context/<task-name>/` for multi-session work.

### Setup

```bash
mkdir -p .claude/context/my-feature
cp .claude/context/templates/*.md .claude/context/my-feature/
```

### Files

| File | Purpose | Update frequency |
|------|---------|------------------|
| `plan.md` | High-level plan and architecture decisions | Rarely |
| `context.md` | Key findings, paths, gotchas | Each session |
| `tasks.md` | Step list and progress | Often |

### Resume prompt

```text
Continue working on my-feature. Resume from where we left off.
```

## Notifications (`ntfy.sh`)

The installer prints your default `ntfy.sh` topic.

Set a custom topic with either method:

```bash
export CLAUDE_NTFY_TOPIC="my-secret-topic"
```

or

```bash
mkdir -p ~/.config/claude-code
echo "my-secret-topic" > ~/.config/claude-code/ntfy_topic
```

Other backends are supported through env vars (Discord webhook, Slack webhook, Pushover).

## Safety Guardrails

### Blocked by default

- Destructive commands (`rm -rf`, `dd`, `mkfs`)
- Privilege escalation (`sudo`, `doas`)
- Remote execution (`curl|bash`, `wget|sh`)
- Risky supply-chain patterns (`npx` unknown packages, `pip install` from URLs)
- Auto git commit/staging commands (unless your automation mode explicitly allows them)

### Protected files

Edits to sensitive files require explicit approval. Examples:

- `.env` (except `.env.example`)
- secrets and credentials
- certs and private keys
- files marked with protected comments

Override only when needed:

```bash
export CLAUDE_ALLOW_PROTECTED_EDITS=1
claude
```

## Customization

Common changes:

- tighten permissions in `.claude/settings.local.json`
- add a safe allowlist pattern in `.claude/hooks/guard_bash.py`
- add protected paths in `.claude/hooks/protect_files.py`
- disable autopilot auto-launch by removing `autopilot_inject.py` from the hook config

## Productivity Tip: Plan Mode for Context Rotation

Use Plan mode instead of `/clear` when context is large.

1. Switch to Plan mode near 50% context
2. Let Claude write a plan from full context
3. Accept the plan and clear context

This keeps the important state and drops the noise.
