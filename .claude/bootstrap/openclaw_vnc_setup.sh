#!/usr/bin/env bash
set -euo pipefail

# OpenClaw VNC Browser Setup
# Provides full Chrome browser UI (tabs, extensions, address bar) via noVNC web viewer

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCLAW_HOME="${OPENCLAW_STATE_DIR:-${OPENCLAW_HOME:-$HOME/.openclaw}}"

log()  { printf "\n==> %s\n" "$*"; }
warn() { printf "\n[WARN] %s\n" "$*" >&2; }
skip() { printf "    [SKIP] %s\n" "$*"; }
has()  { command -v "$1" >/dev/null 2>&1; }

# ── 1) Install dependencies ────────────────────────────────
log "Checking VNC dependencies..."

DEPS_NEEDED=()
for dep in xvfb x11vnc python3; do
  if ! has "$dep"; then
    DEPS_NEEDED+=("$dep")
  fi
done

if [[ ${#DEPS_NEEDED[@]} -gt 0 ]]; then
  log "Installing: ${DEPS_NEEDED[*]}"
  if has apt-get; then
    DEBIAN_FRONTEND=noninteractive
    export DEBIAN_FRONTEND
    python3 -c "import subprocess; subprocess.run(['sudo', 'apt-get', 'update'], check=False)"
    python3 -c "import subprocess; subprocess.run(['sudo', 'apt-get', 'install', '-y'] + '${DEPS_NEEDED[*]}'.split(), check=True)"
  else
    warn "apt-get not found. Install manually: ${DEPS_NEEDED[*]}"
    exit 1
  fi
fi

# ── 2) Create systemd service for Xvfb ────────────────────
log "Creating Xvfb systemd service..."

XVFB_SERVICE="$HOME/.config/systemd/user/openclaw-xvfb.service"
mkdir -p "$(dirname "$XVFB_SERVICE")"

cat > "$XVFB_SERVICE" << 'XVFB_SERVICE_EOF'
[Unit]
Description=Xvfb Virtual Display for OpenClaw Browser
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/Xvfb :99 -screen 0 1920x1080x24 -ac -nolisten tcp
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
XVFB_SERVICE_EOF

log "Created: $XVFB_SERVICE"

# ── 3) Create systemd service for x11vnc ──────────────────
log "Creating x11vnc systemd service..."

X11VNC_SERVICE="$HOME/.config/systemd/user/openclaw-x11vnc.service"

cat > "$X11VNC_SERVICE" << 'X11VNC_SERVICE_EOF'
[Unit]
Description=x11vnc VNC Server for OpenClaw Browser
After=openclaw-xvfb.service
Requires=openclaw-xvfb.service

[Service]
Type=simple
Environment=DISPLAY=:99
ExecStart=/usr/bin/x11vnc -display :99 -forever -shared -rfbport 5900 -nopw
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
X11VNC_SERVICE_EOF

log "Created: $X11VNC_SERVICE"

# ── 4) Install noVNC ───────────────────────────────────────
log "Installing noVNC..."

NOVNC_DIR="$OPENCLAW_HOME/novnc"
if [[ ! -d "$NOVNC_DIR" ]]; then
  python3 -c "
import subprocess, os
os.makedirs('$NOVNC_DIR', exist_ok=True)
subprocess.run(['git', 'clone', '--depth=1', 'https://github.com/novnc/noVNC.git', '$NOVNC_DIR'], check=True)
subprocess.run(['git', 'clone', '--depth=1', 'https://github.com/novnc/websockify.git', '$NOVNC_DIR/utils/websockify'], check=True)
"
  log "Installed noVNC to $NOVNC_DIR"
else
  skip "noVNC already installed at $NOVNC_DIR"
fi

# ── 5) Create systemd service for noVNC ───────────────────
log "Creating noVNC systemd service..."

NOVNC_SERVICE="$HOME/.config/systemd/user/openclaw-novnc.service"

cat > "$NOVNC_SERVICE" << EOF
[Unit]
Description=noVNC Web VNC Client for OpenClaw Browser
After=openclaw-x11vnc.service
Requires=openclaw-x11vnc.service

[Service]
Type=simple
WorkingDirectory=$NOVNC_DIR
ExecStart=$NOVNC_DIR/utils/novnc_proxy --vnc localhost:5900 --listen 6080
Restart=always
RestartSec=3

[Install]
WantedBy=default.target
EOF

log "Created: $NOVNC_SERVICE"

# ── 6) Enable and start services ──────────────────────────
log "Enabling and starting VNC services..."

systemctl --user daemon-reload

for svc in openclaw-xvfb openclaw-x11vnc openclaw-novnc; do
  systemctl --user enable "$svc" 2>/dev/null || true
  systemctl --user restart "$svc"
  log "Started: $svc"
done

# ── 7) Configure OpenClaw browser for headed mode ─────────
log "Configuring OpenClaw browser for headed mode on virtual display..."

if has openclaw; then
  openclaw config set browser.headless false 2>/dev/null || true
  log "Browser set to headed mode (will use DISPLAY=:99)"
fi

# ── 8) Create environment file for browser ────────────────
BROWSER_ENV_FILE="$HOME/.config/systemd/user/openclaw-browser.env"
mkdir -p "$(dirname "$BROWSER_ENV_FILE")"

cat > "$BROWSER_ENV_FILE" << 'BROWSER_ENV_EOF'
DISPLAY=:99
BROWSER_ENV_EOF

log "Created: $BROWSER_ENV_FILE"

# ── 9) Restart gateway to pick up changes ─────────────────
if has openclaw && systemctl --user is-active openclaw-gateway >/dev/null 2>&1; then
  log "Restarting OpenClaw gateway to apply browser config..."
  systemctl --user restart openclaw-gateway
  sleep 5
fi

# ── Summary ────────────────────────────────────────────────
echo ""
echo "======================================"
echo "  VNC Browser Setup Complete"
echo "======================================"
echo ""
echo "  Virtual Display: :99 (1920x1080)"
echo "  VNC Port: 5900"
echo "  noVNC Web Viewer: http://localhost:6080/vnc.html"
echo ""
echo "  Services:"
echo "    systemctl --user status openclaw-xvfb"
echo "    systemctl --user status openclaw-x11vnc"
echo "    systemctl --user status openclaw-novnc"
echo ""
echo "  OpenClaw browser is now in headed mode on the virtual display."
echo "  Start the browser: openclaw browser start"
echo "  Then open the noVNC viewer to see the full Chrome UI."
echo ""
