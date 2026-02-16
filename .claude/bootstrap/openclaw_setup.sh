#!/usr/bin/env bash
set -euo pipefail

# OpenClaw setup for Claude Code Autopilot
# Usage: openclaw_setup.sh [project_dir]

log()  { printf "\n==> %s\n" "$*"; }
warn() { printf "\n[WARN] %s\n" "$*" >&2; }
skip() { printf "    [SKIP] %s\n" "$*"; }
has()  { command -v "$1" >/dev/null 2>&1; }

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

# ---- 2) Copy config template ----
TEMPLATE="${CLAUDE_DIR}/templates/openclaw.json"
CONFIG="${OPENCLAW_HOME}/openclaw.json"

if [[ -f "$TEMPLATE" ]]; then
  if [[ ! -f "$CONFIG" ]]; then
    cp "$TEMPLATE" "$CONFIG"
    # Replace workspace path placeholder
    sed -i "s|__PROJECT_DIR__|${PROJECT_DIR}|g" "$CONFIG" 2>/dev/null || true
    log "Config created: $CONFIG"
  else
    skip "Config already exists: $CONFIG"
  fi
else
  warn "Config template not found: $TEMPLATE"
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

log "OpenClaw setup complete."
echo ""
echo "  Next steps:"
echo "    1. Run: claude setup-token"
echo "    2. Run: openclaw models auth paste-token --provider anthropic"
echo "    3. Start gateway: openclaw gateway start"
echo "    4. (Optional) Setup Discord: openclaw channels add discord"
echo "    5. (Optional) Install daemon: openclaw gateway --install-daemon"
echo ""
