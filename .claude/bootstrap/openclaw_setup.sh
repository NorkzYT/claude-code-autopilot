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

enable_openclaw_plugin_hook() {
  local hook_name="$1"
  if ! has openclaw; then
    return 1
  fi
  if openclaw hooks enable "$hook_name" >/dev/null 2>&1; then
    log "Enabled OpenClaw hook: $hook_name"
    return 0
  fi
  warn "Could not enable OpenClaw hook: $hook_name"
  return 1
}

configure_openclaw_plugin_hooks() {
  if ! has openclaw; then
    return 0
  fi

  log "Configuring OpenClaw plugin hooks..."

  # Use root canonical files (OpenClaw-native locations) plus generated project context.
  openclaw config set hooks.internal.entries.bootstrap-extra-files.paths \
    '["AGENTS.md","TOOLS.md","PROJECT.md","HEARTBEAT.md"]' \
    --json >/dev/null 2>&1 || warn "Failed to set bootstrap-extra-files paths"

  # Best-effort enable of built-in hooks supported on current OpenClaw versions.
  enable_openclaw_plugin_hook "bootstrap-extra-files" || true
  enable_openclaw_plugin_hook "session-memory" || true
  enable_openclaw_plugin_hook "command-logger" || true
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

detect_tailscale_dnsname() {
  if ! has tailscale || ! has python3; then
    return 1
  fi

  tailscale status --json 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception:
    sys.exit(1)
self_info = data.get("Self") or {}
dns = self_info.get("DNSName") or ""
dns = dns.rstrip(".")
if dns:
    print(dns)
else:
    sys.exit(1)
' 2>/dev/null || return 1
}

tailscale_serve_url() {
  if ! has tailscale; then
    return 1
  fi
  tailscale serve status 2>/dev/null | sed -n 's#^\(https://[^ ]*\).*#\1#p' | head -n1
}

ensure_tailscale_serve_https() {
  local target_url="http://127.0.0.1:18789"
  local out=""

  if [[ "$TAILSCALE_DETECTED" != "1" ]]; then
    return 0
  fi
  if ! has tailscale; then
    return 0
  fi

  # If a serve URL already exists, leave it alone.
  if tailscale_serve_url >/dev/null 2>&1 && [[ -n "$(tailscale_serve_url)" ]]; then
    log "Tailscale Serve already configured: $(tailscale_serve_url)"
    return 0
  fi

  log "Configuring Tailscale Serve HTTPS for OpenClaw dashboard..."

  # Newer Tailscale CLI syntax.
  out="$(tailscale serve --bg "$target_url" 2>&1)" && {
    log "Tailscale Serve configured"
    return 0
  }

  # Older syntax fallback.
  if printf '%s' "$out" | grep -qi "CLI for serve and funnel has changed"; then
    out="$(tailscale serve https / "$target_url" 2>&1)" && {
      log "Tailscale Serve configured (legacy syntax)"
      return 0
    }
  fi

  # If non-root lacks permission, try passwordless sudo once.
  if printf '%s' "$out" | grep -qi "Access denied: serve config denied"; then
    if has sudo && sudo -n true 2>/dev/null; then
      out="$(sudo -n tailscale serve --bg "$target_url" 2>&1)" && {
        log "Tailscale Serve configured via sudo"
        return 0
      }
    fi
    warn "Could not configure Tailscale Serve automatically (permission denied)"
    warn "Run one of these manually:"
    warn "  sudo tailscale serve --bg $target_url"
    warn "  sudo tailscale set --operator=$USER   # one-time, then re-run tailscale serve"
    return 1
  fi

  warn "Failed to configure Tailscale Serve automatically"
  printf '%s\n' "$out" | sed 's/^/[WARN]   /' >&2
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
# Internal state path used by this installer. Do not export OPENCLAW_HOME here:
# OpenClaw treats OPENCLAW_HOME as the parent home path, and exporting it as
# ~/.openclaw causes the CLI to look under ~/.openclaw/.openclaw/openclaw.json.
OPENCLAW_HOME="${HOME}/.openclaw"
OPENCLAW_STATE_DIR="${OPENCLAW_HOME}"
export OPENCLAW_STATE_DIR
CLAUDE_DIR="${PROJECT_DIR}/.claude"
OPENCLAW_AUTO_REGISTER="${OPENCLAW_AUTO_REGISTER:-0}"
GATEWAY_HOST="127.0.0.1"
GATEWAY_BIND_MODE="loopback"
TAILSCALE_MODE="off"
TAILSCALE_DNS_NAME=""
TAILSCALE_DETECTED=0

if TS_IP="$(detect_tailscale_ipv4)"; then
  GATEWAY_HOST="$TS_IP"
  GATEWAY_BIND_MODE="loopback"
  TAILSCALE_MODE="serve"
  TAILSCALE_DETECTED=1
  if TS_DNS="$(detect_tailscale_dnsname)"; then
    TAILSCALE_DNS_NAME="$TS_DNS"
  fi
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
  openclaw config set gateway.bind "$GATEWAY_BIND_MODE" 2>/dev/null || true
  openclaw config set gateway.tailscale.mode "$TAILSCALE_MODE" 2>/dev/null || true
  openclaw config set browser.enabled true 2>/dev/null || true
  openclaw config set browser.headless true 2>/dev/null || true
  openclaw config set cron.enabled true 2>/dev/null || true
  openclaw config set browser.downloads.directory "$OPENCLAW_HOME/downloads" 2>/dev/null || true
  log "Config updated via openclaw config set"
  if [[ "$TAILSCALE_DETECTED" == "1" ]]; then
    if [[ -n "$TAILSCALE_DNS_NAME" ]]; then
      log "Detected Tailscale: ${GATEWAY_HOST} (${TAILSCALE_DNS_NAME}); gateway.bind=$GATEWAY_BIND_MODE + gateway.tailscale.mode=$TAILSCALE_MODE"
    else
      log "Detected Tailscale IPv4: $GATEWAY_HOST; gateway.bind=$GATEWAY_BIND_MODE + gateway.tailscale.mode=$TAILSCALE_MODE"
    fi
  else
    skip "Tailscale not detected; gateway bind set to loopback (127.0.0.1), tailscale mode off"
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
  if openclaw workspace set "$PROJECT_DIR" 2>/dev/null; then
    :
  elif openclaw config set agents.defaults.workspace "$PROJECT_DIR" 2>/dev/null; then
    log "Workspace configured via agents.defaults.workspace"
  else
    warn "Failed to set workspace."
  fi
  openclaw setup 2>/dev/null || true
fi

# ---- 7) Install gateway daemon and patch OPENCLAW_STATE_DIR into service ----
if has openclaw; then
  log "Installing gateway daemon..."
  openclaw gateway install --force 2>/dev/null || true

  SERVICE_FILE="$HOME/.config/systemd/user/openclaw-gateway.service"
  if [[ -f "$SERVICE_FILE" ]]; then
    PATCHED_SERVICE_ENV=0
    if grep -q "^Environment=OPENCLAW_STATE_DIR=" "$SERVICE_FILE"; then
      sed -i "s#^Environment=OPENCLAW_STATE_DIR=.*#Environment=OPENCLAW_STATE_DIR=${OPENCLAW_STATE_DIR}#" "$SERVICE_FILE"
      PATCHED_SERVICE_ENV=1
    else
      # Insert under [Service] for compatibility with different unit layouts.
      python3 - "$SERVICE_FILE" "$OPENCLAW_STATE_DIR" <<'PY' 2>/dev/null || true
from pathlib import Path
import sys

p = Path(sys.argv[1])
state_dir = sys.argv[2]
lines = p.read_text().splitlines()
out = []
inserted = False
for i, line in enumerate(lines):
    out.append(line)
    if not inserted and line.strip() == "[Service]":
        out.append(f"Environment=OPENCLAW_STATE_DIR={state_dir}")
        inserted = True
if not inserted:
    out.append("[Service]")
    out.append(f"Environment=OPENCLAW_STATE_DIR={state_dir}")
p.write_text("\n".join(out) + "\n")
PY
      PATCHED_SERVICE_ENV=1
    fi
    if [[ "$PATCHED_SERVICE_ENV" == "1" ]]; then
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

  if [[ "$TAILSCALE_DETECTED" == "1" && "$TAILSCALE_MODE" == "serve" ]]; then
    ensure_tailscale_serve_https || true
  fi

  if gateway_config_paths_match; then
    log "Gateway CLI/service config paths are aligned (single config path in use)"
  else
    warn "Gateway CLI/service config paths appear to differ"
    warn "Run: unset OPENCLAW_HOME; export OPENCLAW_STATE_DIR=\"$OPENCLAW_STATE_DIR\"; openclaw gateway install --force"
    warn "Then verify: openclaw gateway status"
  fi
fi

# ---- 7a) Configure built-in OpenClaw hooks (workflow support) ----
if has openclaw; then
  configure_openclaw_plugin_hooks || true
fi

# ---- 7b) Ensure recommended skills are available (after gateway startup) ----
if has openclaw; then
  log "Ensuring recommended OpenClaw skills are available..."
  for skill in github; do
    ensure_openclaw_skill_available "$skill"
  done
fi

# ---- 7c) Browser ----
# OpenClaw uses its built-in managed browser ("openclaw" profile).
# See https://docs.openclaw.ai/tools/browser
log "Browser: using OpenClaw-managed browser (openclaw profile)"

# ---- 8) Add OPENCLAW_STATE_DIR to shell profiles ----
STATE_EXPORT_LINE="export OPENCLAW_STATE_DIR=\"${OPENCLAW_STATE_DIR}\""
for rcfile in "$HOME/.bashrc" "$HOME/.zshrc"; do
  if [[ -f "$rcfile" ]] || [[ "$(basename "$rcfile")" == ".bashrc" ]]; then
    touch "$rcfile" 2>/dev/null || true
    if ! grep -qF "OPENCLAW_STATE_DIR" "$rcfile" 2>/dev/null; then
      printf '\n# OpenClaw state directory\n%s\n' "$STATE_EXPORT_LINE" >> "$rcfile"
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
echo "    5. (Optional) Setup Discord: bash .claude/bootstrap/openclaw_discord_setup.sh"
echo "       (or: openclaw channels add --channel discord --token <your-bot-token>)"
echo "       (Discord skill becomes ready after channel token is configured)"
echo "    6. (Optional) Check Discord skill readiness: openclaw skills info discord"
echo "    7. Register agent manually (if auto-register was skipped/failed):"
echo "       bash .claude/bootstrap/add_openclaw_agent.sh <name> <path>"
echo "    8. Quick reference (bootstrap scripts + commands):"
echo "       .claude/README-openclaw.md"
echo "  OpenClaw plugin hooks (enabled if supported): bootstrap-extra-files, session-memory, command-logger"
echo "    - These are separate from Claude hooks in .claude/hooks/"
echo ""
echo "  Prompt/agent file updates (.claude/*) -- how changes are picked up:"
echo "    - Re-run the installer (without --with-openclaw) to refresh the repo .claude/ folder."
echo "    - Start a NEW chat/session (Discord: /new) so old context does not keep stale instructions."
echo "    - If OpenClaw behaves stale, run: openclaw gateway start"
echo "    - Template changes (.claude/templates/*) affect future/generated files only;"
echo "      re-run add_openclaw_agent.sh (or install with --with-openclaw) to regenerate root core files."
echo ""
echo "  Gateway is installed as a systemd service and starts automatically."
echo "  Dashboard (local): http://127.0.0.1:18789/"
if [[ "$TAILSCALE_DETECTED" == "1" ]]; then
  if [[ -n "$TAILSCALE_DNS_NAME" ]]; then
    echo "  Dashboard (Tailscale Serve HTTPS): https://${TAILSCALE_DNS_NAME}/"
  else
    echo "  Dashboard (Tailscale Serve HTTPS): use openclaw dashboard or tailscale serve status to get the HTTPS URL"
  fi
  echo "  If Tailscale Serve requires permission, run once:"
  echo "    sudo tailscale set --operator=$USER"
  echo "    tailscale serve --bg http://127.0.0.1:18789"
  echo "  First secure UI connect may require device pairing approval:"
  echo "    openclaw devices list"
  echo "    openclaw devices approve <requestId>"
fi
echo ""
