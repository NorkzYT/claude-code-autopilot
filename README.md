# Claude Code Autopilot Kit (Claude + OpenClaw Engineer Workflow Kit)

A portable `.claude/` bundle for Claude Code with a staged agent workflow, safety hooks, logging, and a strict verification loop.

It also includes OpenClaw setup and bootstrap scripts for remote control, browser automation, multi-agent routing, and cross-session memory.

This repo is built to support a full local engineer workflow:

- fix
- build
- run local stack (`yarn dev`, `make up`, `docker compose up`)
- test
- confirm
- commit and report

The goal is not code-only output. The goal is a repeatable engineering loop.

Once installed, Claude can auto-route substantive tasks into the autopilot pipeline and use OpenClaw when you enable it.

## Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/NorkzYT/claude-code-autopilot/main/install.sh \
  | bash -s -- --repo NorkzYT/claude-code-autopilot --ref main --force --bootstrap-linux
```

After install, you'll see your **ntfy.sh subscription URL** — subscribe to get notified when Claude needs your attention.

Then restart Claude Code to load the new configuration.

> **Note:** Run Claude Code as a **non-root user**. The kit's hooks, logs, and VS Code integration are designed for regular user accounts. If using VS Code Remote (SSH/Tailscale), ensure you attach as the same user that runs Claude.

### Install With OpenClaw (Recommended if you want Discord/browser/multi-agent)

```bash
curl -fsSL https://raw.githubusercontent.com/NorkzYT/claude-code-autopilot/main/install.sh \
  | bash -s -- --repo NorkzYT/claude-code-autopilot --ref main --force --bootstrap-linux --with-openclaw
```

## Start Here

Pick one path:

1. Claude Code only (local terminal workflow): use the Quick Install command above
2. Claude Code + OpenClaw (Discord, browser, remote control): add `--with-openclaw`
3. Refresh an existing repo: re-run the install command with `--force`

What this kit covers:

- Claude Code hooks and guardrails (`.claude/hooks/*`)
- staged agent workflow (autopilot, triage, fixer, closer)
- OpenClaw gateway, Discord, browser, and agent bootstrap scripts
- Codex compatibility layer (`AGENTS.md`, `.agents/skills`, `.codex/rules`)

Then read:

- `.claude/README-openclaw.md` for OpenClaw scripts and common commands
- `.claude/docs/openclaw-integration.md` for full setup and troubleshooting
- `.claude/docs/openclaw-remote-commands.md` for Discord use (slash commands, pairing, allowlists, bindings)

---

## Terminal Names & `cca` Alias

Each Claude Code session gets a **random memorable name** (e.g., `cosmic-penguin`, `thunder-falcon`) so you can easily identify multiple terminals. The name appears in:

- The **terminal tab title**
- **Notification messages** (so you know which terminal needs attention)
- A local identity file at `.claude/terminal-identity.local.json`

Launch Claude with the **`cca` alias** (added to your shell during install):

```bash
cca
```

This runs `claude --dangerously-skip-permissions` with automatic terminal naming. Equivalent to:

```bash
.claude/bin/claude-named --dangerously-skip-permissions
```

> **Note:** After install, open a new shell or run `source ~/.bashrc` (or `~/.zshrc`) to activate the `cca` alias.

---

## How It Works

After installation, the kit automatically:

1. **Injects autopilot** — A hook detects substantive prompts and triggers the autopilot agent
2. **Guards dangerous operations** — Blocks `rm -rf`, `sudo`, `curl|bash`, auto-commits, etc.
3. **Protects sensitive files** — Blocks edits to `.env`, secrets, certs, prod configs
4. **Auto-formats code** — Runs Prettier/Black on edited files when configured
5. **Logs everything** — Prompts, commands, and responses go to `.claude/logs/`

If you install with OpenClaw, it also:

6. **Adds gateway tooling** — Remote access, channel routing, and session management
7. **Adds browser tooling** — Docker Chromium for local UI verification and CDP flows
8. **Bootstraps repo agents** — Generates root OpenClaw core files, `.openclaw/` runtime state, skills, and compatibility files for multi-repo work

---

## Usage Guide

### Just Ask Naturally

For most tasks, simply describe what you want:

```
Add a logout button to the navbar that clears the session and redirects to /login
```

The autopilot agent automatically:
- Explores the codebase to understand the structure
- Plans the implementation
- Makes the changes
- Verifies the result
- Reviews for issues

### Structured Prompts (For Complex Tasks)

For complex or multi-step tasks, use this structure for best results:

```
1) GOAL
- Add user authentication with JWT tokens

2) DEFINITION OF DONE
- [ ] Login endpoint returns JWT on valid credentials
- [ ] Protected routes reject requests without valid token
- [ ] Tests pass

3) CONTEXT
- Using Express.js backend in /src/api
- User model already exists at /src/models/user.js

4) DETAILS
- Use bcrypt for password hashing
- Token expiry: 24 hours
```

### Skip Autopilot for Simple Questions

Simple questions bypass autopilot automatically:

```
What files handle authentication?
How does the routing work?
Explain the database schema
```

---

## Available Agents

| Agent | Use Case | How to Invoke |
|-------|----------|---------------|
| **autopilot** | Full task execution (explore → implement → verify → review) | Automatic for substantive prompts |
| **autopilot-fixer** | Fix incomplete/broken autopilot output | `Use the autopilot-fixer subagent` |
| **closer** | Final verification + PR notes (no new code) | `Use the closer subagent` |
| **triage** | Debug failures (repro → diagnose → fix) | `Use the triage subagent` |
| **parallel-orchestrator** | Multi-part tasks needing parallel work | `Use the parallel-orchestrator subagent` |

### When Autopilot Doesn't Finish

```
Use the autopilot-fixer subagent.

Original Task:
<<<
[paste your original prompt]
>>>

What's Still Wrong:
<<<
[paste error messages or describe the issue]
>>>
```

### Final Verification Before PR

```
Use the closer subagent.

Acceptance Criteria:
<<<
- [ ] Feature works as described
- [ ] Tests pass
- [ ] No console errors
>>>
```

---

## Documentation

The README is the fast path. Detailed guides live in `docs/*.md` and `.claude/docs/*`.

### Core docs (`docs/*.md`)

- `docs/README.md` — documentation index
- `docs/install.md` — install modes, updates, flags, `llms.txt`, git hygiene
- `docs/workflow.md` — session persistence, notifications, guardrails, customization, plan mode
- `docs/editor.md` — external editor (`Ctrl+G`) and VS Code remote setup
- `docs/troubleshooting.md` — common issues and validation commands
- `docs/openclaw.md` — OpenClaw quick guide and hook model overview
- `docs/openclaw-plugin-hooks.md` — plugin hooks and wrapper design for local workflow automation
- `docs/roadmap.md` — roadmap for full engineer workflow enforcement

### OpenClaw docs (repo-local references)

- `.claude/README-openclaw.md` — operator quick reference
- `.claude/docs/openclaw-integration.md` — full setup and operations guide
- `.claude/docs/openclaw-commands.md` — CLI and slash command reference
- `.claude/docs/openclaw-remote-commands.md` — Discord pairing, allowlists, bindings, and channel routing

### Quick reminders

- Use slash commands in Discord first: `/status`, `/help`, `/new`
- `commands.bash=true` is only needed for shell passthrough (`!<cmd>` / `/bash`)
- OpenClaw plugin hooks and `.claude/hooks/*` are separate systems

---

## Core Principles

1. **Smallest change that satisfies the task** — No drive-by refactors
2. **Discovery first** — Search and read before deciding
3. **Always verify** — Run tests/lint/build or provide manual steps
4. **One bounded retry** — Triage → patch → verify once if it fails
5. **No destructive commands** — Unless explicitly approved
