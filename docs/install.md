# Install and Maintenance

This page covers install modes, updates, and common setup files.

## Install Options

### Full bootstrap (Linux)

```bash
curl -fsSL https://raw.githubusercontent.com/NorkzYT/claude-code-autopilot/main/install.sh \
  | bash -s -- --repo NorkzYT/claude-code-autopilot --ref main --force --bootstrap-linux
```

This installs the kit and common dev tools used by the bootstrap scripts.

### Kit only

```bash
curl -fsSL https://raw.githubusercontent.com/NorkzYT/claude-code-autopilot/main/install.sh \
  | bash -s -- --repo NorkzYT/claude-code-autopilot --ref main --force
```

### Update an existing install

Run the same install command with `--force`.

Use `--with-openclaw` only when you want to rerun OpenClaw setup and regenerate `.openclaw/*` files.

## Installer Flags

| Option | Description |
|--------|-------------|
| `--repo <owner/repo>` | Source repo (required) |
| `--ref <branch\|tag\|sha>` | Git ref (default: `main`) |
| `--dest <path>` | Destination (default: current directory) |
| `--force` | Overwrite existing `.claude/` (preserves logs) |
| `--bootstrap-linux` | Full bootstrap (devtools + extras) |
| `--no-extras` | Skip wshobson agents/commands |
| `--with-openclaw` | Run OpenClaw setup and agent bootstrap |

## Project `llms.txt`

This repo includes a template for `llms.txt`.

```bash
cp .claude/docs/llms-txt-template.md ./llms.txt
```

Then edit it for your project.

## Git Hygiene

Add these to your project `.gitignore` if needed:

```gitignore
.claude/logs/
.claude/context/*
!.claude/context/templates/
.claude/vendor/
```

The OpenClaw bootstrap also auto-adds local runtime files and generated root OpenClaw files.

## Optional Extras (wshobson)

When installed with `--bootstrap-linux`, the kit can install curated agents and commands from:

- `wshobson/commands`
- `wshobson/agents`

Manage extras:

```bash
./.claude/extras/install-extras.sh
./.claude/extras/install-extras.sh --update
```
