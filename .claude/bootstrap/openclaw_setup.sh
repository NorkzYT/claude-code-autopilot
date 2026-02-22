#!/usr/bin/env bash
set -euo pipefail

# OpenClaw setup for Claude Code Autopilot
# Usage: openclaw_setup.sh [project_dir]

log()  { printf "\n==> %s\n" "$*"; }
warn() { printf "\n[WARN] %s\n" "$*" >&2; }
skip() { printf "    [SKIP] %s\n" "$*"; }
has()  { command -v "$1" >/dev/null 2>&1; }

openclaw_skill_exists() {
  local skill="$1"
  openclaw skills info "$skill" >/dev/null 2>&1
}

ensure_openclaw_skill_available() {
  local skill="$1"

  if openclaw_skill_exists "$skill"; then
    skip "Skill available: $skill"
    return 0
  fi

  openclaw skills install "$skill" 2>/dev/null && {
    log "Installed skill: $skill"
    return 0
  }

  warn "Failed to install optional skill: $skill"
}

detect_tailscale_ipv4() {
  if ! has tailscale; then
    return 1
  fi

  local ts_ip
  ts_ip="$(tailscale ip -4 2>/dev/null | awk 'NF{print; exit}')"
  if [[ -n "$ts_ip" ]]; then
    printf '%s\n' "$ts_ip"
    return 0
  fi

  return 1
}

gateway_config_paths_match() {
  local status_out cli_path svc_path
  status_out="$(openclaw gateway status 2>&1 || true)"
  cli_path="$(printf '%s\n' "$status_out" | sed -n 's/^Config (cli): //p' | head -n1)"
  svc_path="$(printf '%s\n' "$status_out" | sed -n 's/^Config (service): //p' | head -n1)"
  cli_path="${cli_path%% *}"
  svc_path="${svc_path%% *}"

  [[ -n "$cli_path" && -n "$svc_path" && "$cli_path" == "$svc_path" ]]
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${1:-$(pwd)}"
OPENCLAW_HOME="${HOME}/.openclaw"
OPENCLAW_STATE_DIR="${OPENCLAW_HOME}"
export OPENCLAW_HOME OPENCLAW_STATE_DIR
CLAUDE_DIR="${PROJECT_DIR}/.claude"
OPENCLAW_AUTO_REGISTER="${OPENCLAW_AUTO_REGISTER:-0}"
GATEWAY_HOST="127.0.0.1"

if TS_IP="$(detect_tailscale_ipv4)"; then
  GATEWAY_HOST="$TS_IP"
fi

sanitize_agent_name() {
  local name="$1"
  name="$(echo "$name" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')"
  if [[ -z "$name" ]]; then
    name="agent"
  fi
  if [[ ! "$name" =~ ^[a-z] ]]; then
    name="agent-$name"
  fi
  echo "$name"
}

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
  openclaw config set gateway.bind "$GATEWAY_HOST" 2>/dev/null || true
  openclaw config set browser.enabled true 2>/dev/null || true
  openclaw config set browser.headless true 2>/dev/null || true
  openclaw config set cron.enabled true 2>/dev/null || true
  openclaw config set browser.downloads.directory "$OPENCLAW_HOME/downloads" 2>/dev/null || true
  log "Config updated via openclaw config set"
  if [[ "$GATEWAY_HOST" == "127.0.0.1" ]]; then
    skip "Tailscale IPv4 not detected; gateway bind set to loopback (127.0.0.1)"
  else
    log "Detected Tailscale IPv4: $GATEWAY_HOST (gateway.bind set)"
  fi

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

# ---- 6) Configure workspace ----
if has openclaw; then
  log "Configuring workspace..."
  openclaw workspace set "$PROJECT_DIR" 2>/dev/null || warn "Failed to set workspace."
  openclaw setup 2>/dev/null || true
fi

# ---- 7) Install gateway daemon and patch OPENCLAW_HOME into service ----
if has openclaw; then
  log "Installing gateway daemon..."
  openclaw gateway install --force 2>/dev/null || true

  SERVICE_FILE="$HOME/.config/systemd/user/openclaw-gateway.service"
  if [[ -f "$SERVICE_FILE" ]]; then
    PATCHED_SERVICE_ENV=0
    if ! grep -q "OPENCLAW_HOME" "$SERVICE_FILE"; then
      sed -i "/^Environment=HOME=/a Environment=OPENCLAW_HOME=${OPENCLAW_HOME}" "$SERVICE_FILE"
      log "Patched OPENCLAW_HOME into systemd service"
      PATCHED_SERVICE_ENV=1
    fi
    if ! grep -q "OPENCLAW_STATE_DIR" "$SERVICE_FILE"; then
      sed -i "/^Environment=OPENCLAW_HOME=/a Environment=OPENCLAW_STATE_DIR=${OPENCLAW_STATE_DIR}" "$SERVICE_FILE"
      if ! grep -q "OPENCLAW_STATE_DIR" "$SERVICE_FILE"; then
        sed -i "/^Environment=HOME=/a Environment=OPENCLAW_STATE_DIR=${OPENCLAW_STATE_DIR}" "$SERVICE_FILE"
      fi
      log "Patched OPENCLAW_STATE_DIR into systemd service"
      PATCHED_SERVICE_ENV=1
    fi
    if [[ "$PATCHED_SERVICE_ENV" == "1" ]]; then
      systemctl --user daemon-reload 2>/dev/null || true
    fi
  fi

  # Fix credentials directory permissions (security hardening)
  CREDS_DIR="${OPENCLAW_HOME}/.openclaw/credentials"
  if [[ -d "$CREDS_DIR" ]]; then
    chmod 700 "$CREDS_DIR" 2>/dev/null || true
  fi

  # Start/restart via OpenClaw CLI so startup behavior matches manual recovery guidance.
  log "Starting gateway via OpenClaw CLI..."
  openclaw gateway start 2>/dev/null || warn "Failed to start gateway via OpenClaw CLI. Try: openclaw gateway start"

  if gateway_config_paths_match; then
    log "Gateway CLI/service config paths are aligned (single config path in use)"
  else
    warn "Gateway CLI/service config paths appear to differ"
    warn "Run: export OPENCLAW_HOME=\"$OPENCLAW_HOME\" OPENCLAW_STATE_DIR=\"$OPENCLAW_STATE_DIR\" && openclaw gateway install --force"
    warn "Then verify: openclaw gateway status"
  fi
fi

# ---- 7b) Ensure recommended skills are available (after gateway startup) ----
if has openclaw; then
  log "Ensuring recommended OpenClaw skills are available..."
  for skill in github; do
    ensure_openclaw_skill_available "$skill"
  done
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

# ---- 9) Agent registration ----
ADD_AGENT_SCRIPT="$SCRIPT_DIR/add_openclaw_agent.sh"

if [[ "$OPENCLAW_AUTO_REGISTER" == "1" ]]; then
  if [[ -f "$ADD_AGENT_SCRIPT" ]]; then
    AUTO_AGENT_NAME="${OPENCLAW_AGENT_NAME:-$(basename "$PROJECT_DIR")}"
    AUTO_AGENT_NAME="$(sanitize_agent_name "$AUTO_AGENT_NAME")"
    log "Auto-registering OpenClaw agent '$AUTO_AGENT_NAME' for $PROJECT_DIR ..."
    bash "$ADD_AGENT_SCRIPT" "$AUTO_AGENT_NAME" "$PROJECT_DIR" || warn "Automatic agent registration failed."
  else
    warn "add_openclaw_agent.sh not found at $ADD_AGENT_SCRIPT"
  fi
elif [[ -t 0 ]]; then  # Only if running in a terminal (not piped)
  echo ""
  read -p "Would you like to register a project as an OpenClaw agent? (y/N) " -n 1 -r
  echo ""
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    read -p "Agent name (lowercase, e.g. 'kairo'): " AGENT_REG_NAME
    read -p "Workspace path: " AGENT_REG_PATH
    if [[ -n "$AGENT_REG_NAME" && -n "$AGENT_REG_PATH" && -d "$AGENT_REG_PATH" ]]; then
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
echo "    3. Start gateway (if needed): openclaw gateway start"
echo "    4. Verify: openclaw status"
echo "    5. (Optional) Setup Discord: openclaw channels add discord"
echo "       (Discord skill becomes ready after channel token is configured)"
echo "    6. (Optional) Check Discord skill readiness: openclaw skills info discord"
echo "    7. Register agent manually (if auto-register was skipped/failed):"
echo "       bash .claude/bootstrap/add_openclaw_agent.sh <name> <path>"
echo ""
echo "  Prompt/agent file updates (.claude/*) -- how changes are picked up:"
echo "    - Re-run the installer (without --with-openclaw) to refresh the repo .claude/ folder."
echo "    - Start a NEW chat/session (Discord: /new) so old context does not keep stale instructions."
echo "    - If OpenClaw behaves stale, run: openclaw gateway start"
echo "    - Template changes (.claude/templates/*) affect future/generated files only;"
echo "      re-run add_openclaw_agent.sh (or install with --with-openclaw) to regenerate .openclaw/* files."
echo ""
echo "  Gateway is installed as a systemd service and starts automatically."
echo "  Dashboard: http://${GATEWAY_HOST}:18789/"
echo ""
