# Dev Bridge Skill

> Bridges Discord commands to Claude Code Autopilot for remote development.

## Command Reference

### Task Execution
- `!ship <task>` — Execute full autopilot pipeline via ralph loop
  - Example: `!ship "Add user authentication with JWT"`
  - Runs: `claude --print "Use the autopilot subagent for this task: <task>"`
  - Reports back with completion status and summary

### Testing
- `!test` — Run project test suite
  - Runs: `exec npm test` or `exec python -m pytest` (auto-detect)
  - Returns: pass/fail count, failing test names

### Code Review
- `!review <PR#>` — Review a pull request
  - Runs: `exec gh pr diff <PR#>` then analyzes with Claude
  - Returns: summary, issues found, approval recommendation

### Status
- `!status` — Project status overview
  - Git status (branch, uncommitted changes, ahead/behind)
  - Active tasks from `.claude/context/`
  - Recent cost data from `.claude/logs/cost-tracker.log`
  - Returns: formatted status embed

### Deployment
- `!deploy` — Run deployment checklist
  - Verifies: tests pass, no uncommitted changes, branch up to date
  - Returns: deployment readiness report

### Codebase Queries
- `!ask <question>` — Query the codebase
  - Example: `!ask "How does authentication work?"`
  - Runs: `claude --print "<question>"`
  - Returns: answer with file references

### Scheduling
- `!cron list` — Show scheduled OpenClaw cron jobs
  - Runs: `openclaw cron list`
  - Returns: formatted job list with next run times

### Memory
- `!memory <query>` — Search past session memory
  - Runs: `openclaw memory search "<query>"`
  - Returns: relevant past session context

### Browser
- `!browse <url>` — Navigate to URL and return screenshot
  - Runs: `openclaw browser navigate <url> && openclaw browser screenshot`
  - Returns: screenshot image in Discord

### Data Verification
- `!verify <task>` — Run full data verification pattern
  - Runs: `OPENCLAW_AUTONOMOUS=1 claude --print "Run data verification pattern: <task>"`
  - Returns: discrepancy report with fix status

### HAR Capture
- `!har <url>` — Capture HAR file and return endpoint summary
  - Runs: `openclaw browser har start && openclaw browser navigate <url> && openclaw browser har stop && openclaw browser har analyze`
  - Returns: list of API endpoints found

### Workspace Management
- `!workspace list` — Show configured workspaces
  - Runs: `openclaw workspace list`
  - Returns: workspace names and paths
- `!workspace switch <name>` — Switch active workspace
  - Runs: `openclaw workspace set <name>`
  - Returns: confirmation with new workspace path

### Autonomous Execution
- `!autonomous <task>` — Execute task with autonomous permissions
  - Sets `OPENCLAW_AUTONOMOUS=1` environment
  - Runs: `OPENCLAW_AUTONOMOUS=1 claude --print "Use the autopilot subagent for this task: <task>"`
  - Returns: task report with branch name, commits, test results
  - **Safety:** Creates feature branch, never commits to main

## Implementation Notes

### Exec Translation

All commands translate to either:
1. `exec: claude --print "<translated prompt>"` — For Claude Code tasks
2. `exec: <shell command>` — For direct commands (git status, npm test, etc.)
3. `openclaw <command>` — For OpenClaw-native operations

### Response Formatting

- Use Discord embeds for structured output (title, description, fields, color)
- Green (#00ff00) for success, red (#ff0000) for failures, yellow (#ffff00) for warnings
- Thread replies for outputs longer than 2000 characters
- Code blocks for logs, diffs, and test output

### Error Handling

- Timeout: 5 minutes for `!ship`, 2 minutes for `!test`, 30 seconds for `!status`
- On timeout: report partial results + "Task timed out" message
- On error: report error message with suggestion to check logs

### Safety

- All `exec` commands go through the same safety guardrails as local Claude Code
- No `sudo` or destructive remove commands via Discord
- `!ship` tasks are sandboxed to the configured workspace directory
