# OpenClaw Plugin Hooks and Local Workflow Wrappers

This guide shows how to make the local engineering workflow more automatic with OpenClaw.

## Short Answer: Can this be automated?

Yes, mostly.

The best pattern is:

1. Keep prompt policy in `AGENTS.md` and `TOOLS.md`
2. Use an OpenClaw wrapper command/script for the local workflow steps
3. Use OpenClaw hooks/plugins for runtime logging, memory, and guard checks
4. Keep Discord access locked to approved users/channels

A plugin hook alone is not enough to enforce the full workflow order. A wrapper script is the stable path.

## Two Hook Systems (Important)

This repo uses two different hook systems:

- `.claude/hooks/*` — Claude Code hooks (local prompt/tool guardrails)
- `openclaw hooks ...` — OpenClaw gateway hooks (runtime features)

Use both.

## OpenClaw Hook Types

### Built-in / normal hooks

These can often be enabled directly:

```bash
openclaw hooks list
openclaw hooks enable bootstrap-extra-files
openclaw hooks enable session-memory
openclaw hooks enable command-logger
```

### Plugin-managed hooks

Some hooks appear as `plugin:<id>`.

These are managed by plugins. You usually:

- enable or disable the plugin
- configure the plugin
- do not enable the `plugin:<id>` hook directly

This matters when reading `openclaw hooks list` output.

## What We Already Use in This Repo

The OpenClaw setup script tries to enable these hooks (if supported):

- `bootstrap-extra-files`
- `session-memory`
- `command-logger`

It also configures `bootstrap-extra-files` to include generated workspace files like:

- `AGENTS.md`
- `TOOLS.md`
- `PROJECT.md`
- `HEARTBEAT.md`

## Recommended Automation Pattern (Local Workflow)

Use one wrapper script that runs the local workflow in order:

1. Build
2. Run local stack (or restart local services)
3. Test
4. Confirm (smoke check)
5. Print a structured summary

Then call that wrapper from:

- a custom OpenClaw command
- a plugin action
- a Discord-triggered workflow command
- a cron job (for repeatable verification tasks)

## Real Wrapper and Plugin (Included)

A supported repo-local wrapper script is included here:

- `.claude/scripts/openclaw-local-workflow.sh`

It reads commands from `TOOLS.md` and runs a local workflow in a predictable order.

This repo also includes a real OpenClaw plugin:

- `.claude/openclaw-plugins/local-workflow-wrapper/`

It registers:

- `/localflow` — run build -> run-local -> test -> confirm
- `/workflowcheck` — read the latest `.openclaw/workflow-report.local.json`

And a plugin hook:

- `command:new` — clears stale workflow report files when a new session starts

## How to Wire It (Design)

### Option A: Manual shell use (fastest)

```bash
bash .claude/scripts/openclaw-local-workflow.sh --repo /path/to/repo
```

### Option B: OpenClaw custom command wrapper (recommended, implemented)

Use the bundled plugin commands after agent bootstrap installs/enables the plugin:

```text
/localflow
/workflowcheck
```

They resolve the workspace from the bound agent/session when possible and accept overrides:

```text
/localflow --agent <agent-id>
/localflow --repo /path/to/repo
```

### Option C: Plugin hook + wrapper (strict mode)

Use a plugin or plugin-managed hook to require a report schema before marking work complete.

Design idea:

- wrapper writes `workflow-report.json`
- plugin hook checks file exists and steps passed
- completion/report path fails if report is missing

Reference examples and checks:

- `docs/examples/openclaw-workflow-report-check.sh`
- `docs/examples/openclaw-workflow-enforcer-plugin/`

## What This Enforces vs What It Does Not

### Enforces well

- Step order when using the wrapper
- Repeatable local commands
- Consistent summary output
- Lower chance of code-only "done"

### Does not enforce by itself

- Free-form chat responses that never call the wrapper
- Manual claims without evidence

That is why you should use:

- Discord allowlists
- slash commands
- wrapper commands
- exec approvals
- optional plugin checks

## Security Notes

- Keep `commands.bash=false` unless you need shell passthrough
- If you enable bash passthrough, use guild/channel/user allowlists
- Keep dangerous commands blocked in `.claude/hooks/guard_bash.py`
- Use feature branches and commit-msg hook enforcement
