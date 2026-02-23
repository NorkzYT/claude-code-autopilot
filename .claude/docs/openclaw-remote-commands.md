# OpenClaw Remote Use (Discord)

This guide shows the safe, version-stable way to use OpenClaw from Discord.

## Start Here

Use slash commands first on OpenClaw 2026.2.x:

- `/status`
- `/help`
- `/new`
- `/reset`

Do not assume `!status`, `!ship`, or other `!` commands exist. Those may be custom workflows in some setups.

## Why `!status` May Fail

If Discord replies with `bash is disabled`, OpenClaw treated `!status` as shell passthrough.

That means:

- `!status` is not a built-in command on your version
- `commands.bash` is disabled (secure default)

Use `/status` instead.

## Pairing and Access Checks

Discord use can fail for three different reasons. Fix them in this order.

### 1) Bot connection

Check that the bot is online and the channel is configured:

```bash
openclaw channels status
openclaw logs --follow
```

### 2) Pairing (DM / secure sessions)

First-time secure use may require pairing.

```bash
openclaw pairing list discord
openclaw pairing approve discord <code>
```

### 3) Guild / channel / user allowlist

DM access and server channel access are separate.

If Discord says `This channel is not allowed` or `You are not authorized to use this command`, lock access to one guild, one channel, and one user.

Use the setup wizard:

```bash
bash .claude/bootstrap/openclaw_discord_setup.sh
```

Or configure it manually in `~/.openclaw/openclaw.json` under `channels.discord`.

## Bind a Discord Channel to an Agent

Bind a channel to a specific agent so `/new` starts sessions on that repo agent instead of `main`.

Example:

```bash
openclaw config set bindings '[{"agentId":"my-agent","match":{"channel":"discord","guildId":"<guild-id>","peer":{"kind":"channel","id":"<channel-id>"}}}]' --json
openclaw gateway start
```

Then start a fresh session in Discord:

```text
/new
```

Confirm with:

```text
/status
```

You should see:

- `Session: agent:my-agent:discord:channel:<channel-id>`

## Local Engineering Workflow from Discord

This kit is tuned for local developer workflows, not staging or production deploys.

Expected flow:

1. Fix the code
2. Build
3. Run or reload the local stack (`yarn dev`, `make up`, `docker compose up`)
4. Test
5. Confirm the changed flow locally
6. Commit and report

Notes:

- Slash commands manage sessions and status
- Agent tool execution handles most local commands
- `commands.bash=true` is only needed if you want direct shell passthrough (`!<cmd>` / `/bash`)

## When to Enable `commands.bash`

Keep it off unless you need direct shell commands from Discord.

Enable only if you trust the channel and the allowlist is locked down:

```bash
openclaw config set commands.bash true
openclaw gateway start
```

## Troubleshooting

### No reply in a server channel

- Check bot permissions: View Channel, Send Messages, Use Application Commands
- Check allowlist config: `openclaw config get channels.discord --json`
- Use `/status` instead of `!status`

### Bot replies in DM and not in server

Server policy is blocked. Configure:

- `channels.discord.groupPolicy`
- guild/channel allowlist
- guild user allowlist

### Wrong repo agent in channel

Set a Discord channel binding and start a new session (`/new`).
