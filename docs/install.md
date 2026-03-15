# Install and Maintenance

This page covers install modes, updates, and common setup files.

## Install Options

### Full bootstrap (Linux)

```bash
curl -fsSL https://raw.githubusercontent.com/NorkzYT/claude-code-autopilot/main/install.sh \
  | bash -s -- --repo NorkzYT/claude-code-autopilot --ref main --force --bootstrap-linux
```

### Kit only

```bash
curl -fsSL https://raw.githubusercontent.com/NorkzYT/claude-code-autopilot/main/install.sh \
  | bash -s -- --repo NorkzYT/claude-code-autopilot --ref main --force
```

### Update an existing install

Run the same install command with `--force`.

Use `--with-openclaw` to configure the Docker-only OpenClaw stack and wrapper.
Use `--with-crewai` when you want to scaffold or refresh `.crewai/*` assets.

## Installer Flags

| Option | Description |
|--------|-------------|
| `--repo <owner/repo>` | Source repo (required) |
| `--ref <branch\|tag\|sha>` | Git ref (default: `main`) |
| `--dest <path>` | Destination (default: current directory) |
| `--force` | Overwrite existing `.claude/` (preserves logs) |
| `--bootstrap-linux` | Full bootstrap (devtools + extras) |
| `--no-extras` | Skip wshobson agents/commands |
| `--with-openclaw` | Configure Docker-only OpenClaw and install the host wrapper |
| `--open-claw` | Alias for `--with-openclaw` |
| `--with-crewai` | Run CrewAI setup and scaffold `.crewai/` |
| `--crewAI` | Alias for `--with-crewai` |

## OpenClaw Environment File

The OpenClaw Docker stack uses `.env.example` as the canonical reference. Copy it to `.env` if you need to set:

- `HOST_REPOS_DIR`
- gateway and viewer ports
- git author and committer identity
- `OPENCLAW_MODEL_PRIMARY=anthropic/claude-sonnet-4-6`
- `OPENCLAW_THINKING_DEFAULT=high`
- `OPENCLAW_ANTHROPIC_SETUP_TOKEN`
- `ANTHROPIC_API_KEY` / `OPENAI_API_KEY`
- Discord token placeholders
- browser width and downloads directory

## Git Hygiene

Add these to your project `.gitignore` if needed:

```gitignore
.claude/logs/
.claude/context/*
!.claude/context/templates/
.claude/vendor/
```
