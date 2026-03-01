# OpenClaw Setup (Quick Guide)

This page is a short entry point. The full OpenClaw guides live in `.claude/docs/`.

## What OpenClaw Adds

- Discord remote control (slash commands and channel bindings)
- Browser automation (OpenClaw-managed browser + Chrome extension relay)
- Cron jobs and automation
- Gateway and multi-agent routing
- Cross-session memory and search

## Quick Setup

```bash
curl -fsSL https://raw.githubusercontent.com/NorkzYT/claude-code-autopilot/main/install.sh \
  | bash -s -- --repo NorkzYT/claude-code-autopilot --ref main --force --bootstrap-linux --with-openclaw
```

Then follow the prompt output:

1. `claude setup-token`
2. `openclaw models auth paste-token --provider anthropic`
3. `openclaw gateway start`
4. `bash .claude/bootstrap/openclaw_discord_setup.sh` (optional)
5. `bash .claude/bootstrap/add_openclaw_agent.sh <agent-id> <repo-path>` (for extra repos)

Important:
- `PROJECT.md` is generated only by deep analysis.
- If you run `analyze_repo.sh` manually, include `--deep`:
  - `bash .claude/bootstrap/analyze_repo.sh <repo-path> --deep`
- Auto-generated `PROJECT.md` files (from `analyze_repo.sh`) can be refreshed by re-running `--deep`.
- Custom/manual `PROJECT.md` files are preserved and not overwritten.
- To wait for Claude completion without timeout wrapper:
  - `CLAUDE_DEEP_NO_TIMEOUT=1 bash .claude/bootstrap/analyze_repo.sh <repo-path> --deep`

## Add a New Repo Agent

Recommended (uses this repo's bootstrap automation):

```bash
bash .claude/bootstrap/add_openclaw_agent.sh <agent-id> <repo-path>
```

Example:

```bash
bash .claude/bootstrap/add_openclaw_agent.sh myproject /opt/github/myproject
```

Direct OpenClaw CLI (minimal registration only):

```bash
openclaw agents add <agent-id> --workspace <repo-path> --non-interactive
```

## One Agent -> One Discord Channel (Seamless Flow)

Use this exact sequence when you want a repo agent pinned to one Discord channel.

1. Register the repo as an agent:

```bash
bash .claude/bootstrap/add_openclaw_agent.sh <agent-id> <repo-path>
```

2. Ensure Discord channel integration is configured:

```bash
bash .claude/bootstrap/openclaw_discord_setup.sh
```

3. Run the lane/concurrency wizard and enter:
   - your Discord Server ID (guild)
   - your Discord user ID
   - `Require @mention ...`: choose `n` if you want always-on plain-text
   - `Max concurrent runs`: choose `1` for strict one-task-at-a-time in this lane (or higher if needed)
   - primary Discord channel ID
   - primary agent ID (same `<agent-id>` you registered)

```bash
bash .claude/bootstrap/openclaw_discord_scale_setup.sh
```

4. In that Discord channel, start a fresh session and verify routing:
   - run `/new`
   - run `/status`
   - confirm session includes: `agent:<agent-id>:discord:channel:<channel-id>`

5. Verify config on host:

```bash
openclaw config get bindings --json
openclaw config get channels.discord --json
openclaw status --deep
```

Notes:
- If `/status` still shows `Activation: mention` after `/new`, run the scale wizard again and then start a fresh `/new`.
- The scale wizard writes both guild-level and channel-level `requireMention` policy.

## Add Concurrency (Bash Script)

Use the OpenClaw scaling wizard:

```bash
bash .claude/bootstrap/openclaw_discord_scale_setup.sh
```

This configures:

- strict Discord allowlist (guild + user + channels)
- channel -> agent lane bindings
- `agents.defaults.maxConcurrent`
- guild-level + channel-level `requireMention` policy
- thread-first parallel workflow (one thread per task)

Recommended usage model:

1. Keep one lane per channel.
2. Create multiple Discord threads in that channel.
3. Run `/new` in each thread and execute tasks in parallel.

Verify applied config:

```bash
openclaw config get channels.discord --json
openclaw config get bindings --json
openclaw status --deep
```

If `/status` still shows `Activation: mention` right after `/new`, rerun the scale wizard and then start a fresh session with `/new`.

## Discord (OpenClaw 2026.2.x)

Use slash commands first:

- `/status`
- `/help`
- `/new`
- `/recheckin 5m Re-check the task and report back in this channel.`

If `!status` says `bash is disabled`, that is expected on secure setups. Use slash commands and only enable `commands.bash=true` if you want shell passthrough.
Do not use plain text promises like "I'll check back in 5 minutes" unless a real cron job is created. Use `/recheckin`.

## Browser Access to Local Apps

Yes, OpenClaw can verify local frontends and local APIs while you develop.

- OpenClaw-managed browser (`openclaw` profile): `http://localhost:<port>` works directly
- Chrome extension relay (`chrome` profile): `http://localhost:<port>` works directly

## Hook Model

This repo uses two hook systems:

- `.claude/hooks/*` (Claude Code hooks)
- OpenClaw plugin hooks (`openclaw hooks ...`) for gateway runtime features

The setup script tries to enable supported OpenClaw hooks like:

- `bootstrap-extra-files`
- `session-memory`
- `command-logger`

Plugin-managed hooks are different. They are registered by plugins and appear in `openclaw hooks list` as `plugin:<id>`. You enable or disable the plugin, not the individual plugin-managed hook.

## Local Workflow Wrapper (Recommended)

This repo includes a local workflow wrapper for engineering verification:

```bash
bash .claude/scripts/openclaw-local-workflow.sh --repo /path/to/repo
```

It runs:

1. Build
2. Run local stack
3. Test
4. Confirm (smoke check)

See `docs/openclaw-plugin-hooks.md` for how to wire it into OpenClaw command wrappers and plugin hooks.

## Full OpenClaw Docs in This Repo

- `.claude/README-openclaw.md` — operator quick reference
- `.claude/docs/openclaw-integration.md` — full setup and ops guide
- `.claude/docs/openclaw-commands.md` — CLI and slash command reference
- `.claude/docs/openclaw-remote-commands.md` — Discord pairing, allowlists, bindings, channel routing

## Docker Stack (OpenClaw + CrewAI)

Use the OpenClaw-only compose file:

```bash
docker compose -f docker-compose.openclaw.yml up -d
```

This mounts `/opt/repos` into the OpenClaw container so one gateway can work across many repos/agents.

See:
- `docs/docker-openclaw-crewai.md` for all commands
- OpenClaw Docker docs: `https://docs.openclaw.ai/install/docker`
- OpenClaw sandbox docs: `https://docs.openclaw.ai/gateway/sandboxing`
