# OpenClaw Remote Commands Reference

> Commands available via Discord (and other OpenClaw channels) for remote development.

## Quick Reference

| Command | Description | Timeout |
|---------|-------------|---------|
| `!ship <task>` | Execute full autopilot pipeline | 5 min |
| `!test` | Run project test suite | 2 min |
| `!review <PR#>` | Review a pull request | 3 min |
| `!status` | Project status overview | 30 sec |
| `!deploy` | Deployment readiness check | 2 min |
| `!ask <question>` | Query the codebase | 1 min |
| `!cron list` | Show scheduled jobs | 10 sec |
| `!memory <query>` | Search session memory | 15 sec |

## Detailed Command Reference

### `!ship <task>`

Execute a complete development task using the autopilot pipeline.

**Examples:**
```
!ship "Add input validation to the login form"
!ship "Fix the failing test in auth.test.js"
!ship "Refactor database queries to use connection pooling"
```

**What happens:**
1. OpenClaw receives the command via Discord
2. Translates to: `claude --print "Use the autopilot subagent for this task: <task>"`
3. Autopilot explores, plans, implements, verifies, reviews
4. Results posted back to Discord thread

**Response format:**
- Success: Green embed with summary of changes, files modified, tests status
- Failure: Red embed with error details and suggested next steps

### `!test`

Run the project's test suite and report results.

**Examples:**
```
!test
!test --verbose
```

**What happens:**
1. Auto-detects test runner (npm test, pytest, etc.)
2. Runs tests
3. Reports pass/fail counts and failing test names

### `!review <PR#>`

Review a GitHub pull request.

**Examples:**
```
!review 42
!review 123
```

**What happens:**
1. Fetches PR diff via `gh pr diff <PR#>`
2. Analyzes changes with Claude
3. Reports: summary, potential issues, approval recommendation

### `!status`

Get a quick overview of the project state.

**Response includes:**
- Current git branch and status
- Uncommitted changes count
- Active tasks (from `.claude/context/`)
- Today's token usage (from cost tracker)
- OpenClaw gateway status

### `!deploy`

Run a deployment readiness checklist.

**Checks:**
- [ ] All tests pass
- [ ] No uncommitted changes
- [ ] Branch is up to date with remote
- [ ] No high/critical dependency vulnerabilities
- [ ] Lint passes (if configured)

### `!ask <question>`

Ask a question about the codebase.

**Examples:**
```
!ask "How does the authentication middleware work?"
!ask "What files handle API routing?"
!ask "Explain the database schema"
```

### `!cron list`

Show all configured cron jobs and their status.

**Response includes:**
- Job name and schedule
- Last run time and status
- Next scheduled run

### `!memory <query>`

Search past session memory using OpenClaw's RAG system.

**Examples:**
```
!memory "how did we fix the auth bug"
!memory "database migration approach"
```

## Discord Formatting

- Success responses: Green embeds (#00ff00)
- Error responses: Red embeds (#ff0000)
- Warning responses: Yellow embeds (#ffff00)
- Long outputs: Threaded replies with code blocks
- File diffs: Syntax-highlighted code blocks

## Safety

All remote commands operate under the same safety guardrails as local Claude Code:
- No `sudo` or destructive commands (recursive deletes, force operations, etc.)
- Protected files (`.env`, secrets, certs) cannot be modified
- All operations logged to `.claude/logs/`
- Workspace sandboxed to configured project directory

## Setup

See `.claude/docs/openclaw-integration.md` for full setup instructions, or run:
```bash
bash .claude/bootstrap/openclaw_discord_setup.sh
```
