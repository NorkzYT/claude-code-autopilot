#!/usr/bin/env bash
set -euo pipefail

# OpenClaw setup for Claude Code Autopilot
# Usage: openclaw_setup.sh [project_dir]

log()  { printf "\n==> %s\n" "$*"; }
warn() { printf "\n[WARN] %s\n" "$*" >&2; }
skip() { printf "    [SKIP] %s\n" "$*"; }
has()  { command -v "$1" >/dev/null 2>&1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${1:-$(pwd)}"
OPENCLAW_HOME="${HOME}/.openclaw"
CLAUDE_DIR="${PROJECT_DIR}/.claude"

# ---- 0) Verify prerequisites ----
if ! has node; then
  warn "Node.js not found. OpenClaw requires Node.js 22+."
  exit 1
fi

NODE_MAJOR="$(node -v 2>/dev/null | sed -E 's/^v([0-9]+)\..*/\1/' || echo 0)"
if [[ "$NODE_MAJOR" -lt 22 ]]; then
  warn "OpenClaw requires Node.js 22+. Current: $(node -v). Please upgrade."
  exit 1
fi

if ! has openclaw; then
  log "Installing OpenClaw globally..."
  npm install -g openclaw@latest || { warn "Failed to install openclaw."; exit 1; }
fi

log "OpenClaw version: $(openclaw --version 2>/dev/null || echo 'unknown')"

# ---- 1) Create directory structure ----
log "Setting up OpenClaw workspace..."
mkdir -p "$OPENCLAW_HOME"
mkdir -p "$OPENCLAW_HOME/memory/claude-sessions"
mkdir -p "$OPENCLAW_HOME/skills"
mkdir -p "$OPENCLAW_HOME/downloads"

# ---- 2) Configure OpenClaw via CLI (respects schema) ----
if has openclaw; then
  log "Configuring OpenClaw settings..."
  openclaw config set gateway.mode local 2>/dev/null || true
  openclaw config set gateway.port 18789 2>/dev/null || true
  openclaw config set browser.enabled true 2>/dev/null || true
  openclaw config set browser.headless true 2>/dev/null || true
  openclaw config set cron.enabled true 2>/dev/null || true
  openclaw config set browser.downloads.directory "$OPENCLAW_HOME/downloads" 2>/dev/null || true
  log "Config updated via openclaw config set"

  # Optional: headed mode for extension testing (uncomment if needed)
  # openclaw config set browser.headless false 2>/dev/null || true
fi

# ---- 3) Copy agent instructions template ----
AGENTS_TEMPLATE="${CLAUDE_DIR}/templates/AGENTS.md"
AGENTS_DEST="${OPENCLAW_HOME}/AGENTS.md"

if [[ -f "$AGENTS_TEMPLATE" && ! -f "$AGENTS_DEST" ]]; then
  cp "$AGENTS_TEMPLATE" "$AGENTS_DEST"
  log "Agent instructions created: $AGENTS_DEST"
fi

# ---- 4) Copy heartbeat template ----
HEARTBEAT_TEMPLATE="${CLAUDE_DIR}/templates/HEARTBEAT.md"
HEARTBEAT_DEST="${OPENCLAW_HOME}/HEARTBEAT.md"

if [[ -f "$HEARTBEAT_TEMPLATE" && ! -f "$HEARTBEAT_DEST" ]]; then
  cp "$HEARTBEAT_TEMPLATE" "$HEARTBEAT_DEST"
  log "Heartbeat checklist created: $HEARTBEAT_DEST"
fi

# ---- 5) Auth guidance ----
log "Claude Max Authentication Setup"
echo ""
echo "  To authenticate with Claude Max subscription:"
echo ""
echo "  1. Generate a setup token:"
echo "     claude setup-token"
echo ""
echo "  2. Paste the token into OpenClaw:"
echo "     openclaw models auth paste-token --provider anthropic"
echo ""
echo "  3. Verify auth is active:"
echo "     openclaw models status"
echo ""

# ---- 6) Install recommended ClawHub skills ----
if has openclaw; then
  log "Installing recommended ClawHub skills..."
  for skill in github docker monitoring; do
    openclaw skills install "$skill" 2>/dev/null || warn "Failed to install skill: $skill"
  done
fi

# ---- 7) Configure workspace ----
if has openclaw; then
  log "Configuring workspace..."
  openclaw workspace set "$PROJECT_DIR" 2>/dev/null || warn "Failed to set workspace."
  openclaw setup 2>/dev/null || true
fi

# ---- 7b) Install gateway daemon and patch OPENCLAW_HOME into service ----
if has openclaw; then
  log "Installing gateway daemon..."
  openclaw gateway install 2>/dev/null || true

  SERVICE_FILE="$HOME/.config/systemd/user/openclaw-gateway.service"
  if [[ -f "$SERVICE_FILE" ]]; then
    if ! grep -q "OPENCLAW_HOME" "$SERVICE_FILE"; then
      sed -i "/^Environment=HOME=/a Environment=OPENCLAW_HOME=${OPENCLAW_HOME}" "$SERVICE_FILE"
      systemctl --user daemon-reload 2>/dev/null || true
      log "Patched OPENCLAW_HOME into systemd service"
    fi
  fi

  # Fix credentials directory permissions (security hardening)
  CREDS_DIR="${OPENCLAW_HOME}/.openclaw/credentials"
  if [[ -d "$CREDS_DIR" ]]; then
    chmod 700 "$CREDS_DIR" 2>/dev/null || true
  fi

  # Start gateway service
  systemctl --user start openclaw-gateway.service 2>/dev/null || true
fi

# ---- 7c) Browser setup (Docker-based) ----
BROWSER_SCRIPT="$SCRIPT_DIR/openclaw_browser_setup.sh"
if [[ -f "$BROWSER_SCRIPT" ]]; then
  log "Setting up Docker-based browser..."
  chmod +x "$BROWSER_SCRIPT" 2>/dev/null || true
  bash "$BROWSER_SCRIPT"
fi

# ---- 8) Add OPENCLAW_HOME to shell profiles ----
EXPORT_LINE="export OPENCLAW_HOME=\"${OPENCLAW_HOME}\""
for rcfile in "$HOME/.bashrc" "$HOME/.zshrc"; do
  if [[ -f "$rcfile" ]] || [[ "$(basename "$rcfile")" == ".bashrc" ]]; then
    touch "$rcfile" 2>/dev/null || true
    if ! grep -qF "OPENCLAW_HOME" "$rcfile" 2>/dev/null; then
      printf '\n# OpenClaw home directory\n%s\n' "$EXPORT_LINE" >> "$rcfile"
    fi
  fi
done

# ---- 9) Interactive agent registration ----
if [[ -t 0 ]]; then  # Only if running in a terminal (not piped)
  echo ""
  read -p "Would you like to register a project as an OpenClaw agent? (y/N) " -n 1 -r
  echo ""
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    read -p "Agent name (lowercase, e.g. 'kairo'): " AGENT_REG_NAME
    read -p "Workspace path: " AGENT_REG_PATH
    if [[ -n "$AGENT_REG_NAME" && -n "$AGENT_REG_PATH" && -d "$AGENT_REG_PATH" ]]; then
      ADD_AGENT_SCRIPT="$SCRIPT_DIR/add_openclaw_agent.sh"
      if [[ -f "$ADD_AGENT_SCRIPT" ]]; then
        bash "$ADD_AGENT_SCRIPT" "$AGENT_REG_NAME" "$AGENT_REG_PATH"
      else
        warn "add_openclaw_agent.sh not found at $ADD_AGENT_SCRIPT"
      fi
    else
      warn "Invalid agent name or workspace path."
    fi
  fi
fi

log "OpenClaw setup complete."
echo ""
echo "  Next steps:"
echo "    1. Run: claude setup-token"
echo "    2. Run: openclaw models auth paste-token --provider anthropic"
echo "    3. Verify: openclaw status"
echo "    4. (Optional) Setup Discord: openclaw channels add discord"
echo "    5. Add project agents: bash .claude/bootstrap/add_openclaw_agent.sh <name> <path>"
echo ""
echo "  Gateway is installed as a systemd service and starts automatically."
echo "  Dashboard: http://127.0.0.1:18789/"
echo ""
