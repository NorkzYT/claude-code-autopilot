# Troubleshooting

## Common Issues

| Issue | What to check |
|-------|---------------|
| Autopilot not launching | Restart Claude Code and confirm `.claude/settings.local.json` exists |
| Command blocked | Review `.claude/hooks/guard_bash.py` and add a safe allowlist rule if needed |
| File edit blocked | Check protected file markers and sentinel rules |
| Formatting not working | Make sure the repo has formatter config files (`.prettierrc*`, `pyproject.toml`) |
| Hooks not running | Ensure the settings file used by Claude includes the hook config |
| `Ctrl+G` opens `nano` | Confirm VS Code integration requirements from `docs/editor.md` |

## Validate the kit setup

```bash
./.claude/extras/doctor.sh
```

## Agent Stops Mid-Task (Requires "Continue")

**Symptom:** The agent stops during a long-running task and requires the user to say "Continue." to resume.

**Log signature** (in `make logs`):
```
[agent/embedded] embedded run timeout: runId=... timeoutMs=600000
[agent/embedded] Profile anthropic:manual timed out. Trying next account...
[agent/embedded] embedded run failover decision: ... decision=surface_error reason=timeout
```

**Cause:** OpenClaw's default embedded run timeout is 600 seconds (10 minutes). Complex multi-step tasks exceed this limit.

**Fix:**

```bash
# Set to 2 hours (recommended) — applied automatically on next make update-agent
make set-timeout TIMEOUT=7200

# Or set directly inside the container
make shell
openclaw config set agents.defaults.timeoutSeconds 7200
```

Re-provisioning an agent with `make update-agent` also applies the 7200s default automatically.

**Verify:**
```bash
make shell
openclaw config get agents.defaults.timeoutSeconds
# Should output: 7200
```

## OpenClaw Troubleshooting

Use the OpenClaw docs for gateway, Discord, and browser issues:

- `.claude/docs/openclaw-integration.md`
- `.claude/docs/openclaw-remote-commands.md`
- `.claude/docs/openclaw-commands.md`

Useful commands:

```bash
make status
make doctor
make logs
```
