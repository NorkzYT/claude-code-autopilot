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

## Can't Access Host localhost From Container

**Symptom:** An agent inside the Docker container can't reach a dev server running on the host at `127.0.0.1:<port>`. `curl http://127.0.0.1:4000` fails with "Connection refused".

**Cause:** `127.0.0.1` inside the container is the container's own loopback, not the host's. Services bound to `127.0.0.1` on the host don't listen on the Docker bridge interface.

**Fix — Option A: Bind the dev server to `0.0.0.0`**

If possible, start your dev server on `0.0.0.0:<port>` instead of `127.0.0.1:<port>`. Then use `host.docker.internal:<port>` from inside the container.

**Fix — Option B: Use host networking mode**

```bash
make start-host    # or: make restart-host
```

This uses `network_mode: host` so the container shares the host's network stack. `127.0.0.1:4000` on the host IS `127.0.0.1:4000` in the container.

To switch back to normal bridge networking:

```bash
make start         # or: make restart
```

**Note:** In host networking mode, the gateway port is no longer mapped — it binds directly to the host. The browser viewer still works via `http://<host>:6080`.

## Browser Contention With Multiple Agents

**Symptom:** Multiple agents interfere with each other's browser tabs, navigation, or session state.

**Cause:** By default, all agents share a single Chromium instance (one X display :99, one CDP port, one profile).

**Fix:** Enable per-agent browser isolation:

1. Set `OPENCLAW_BROWSER_ISOLATION=per-agent` in your `.env` file
2. Rebuild: `make rebuild && make restart`

Each agent gets its own virtual X display (:100–:119), Chromium profile, and CDP port (18801–18820). The shared display :99 continues to serve the VNC viewer for manual use.

**Verify:**
```bash
make shell
ps aux | grep Xvfb                 # Should show :99 + per-agent displays
ls ~/.openclaw/browser-profiles/   # Per-agent profile directories
ls ~/.openclaw/display-locks/      # Active lock files
```

**Rollback:** Set `OPENCLAW_BROWSER_ISOLATION=shared` (or remove it) and `make rebuild`.

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
