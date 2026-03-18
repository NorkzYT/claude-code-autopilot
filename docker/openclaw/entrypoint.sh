#!/usr/bin/env bash
set -euo pipefail

mode="${1:-gateway}"
if [[ $# -gt 0 ]]; then
  shift
fi

# Align container node user UID/GID with host user (avoids permission conflicts on bind mounts)
PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

current_uid=$(id -u node)
current_gid=$(id -g node)

if [[ "$PGID" != "$current_gid" ]]; then
  groupmod -o -g "$PGID" node 2>/dev/null || true
fi
if [[ "$PUID" != "$current_uid" ]]; then
  usermod -o -u "$PUID" node 2>/dev/null || true
fi

OPENCLAW_STATE_DIR="${OPENCLAW_STATE_DIR:-/home/node/.openclaw}"
OPENCLAW_BROWSER_DOWNLOADS_DIR="${OPENCLAW_BROWSER_DOWNLOADS_DIR:-$OPENCLAW_STATE_DIR/downloads}"
OPENCLAW_BROWSER_WIDTH="${OPENCLAW_BROWSER_WIDTH:-1920}"
OPENCLAW_BROWSER_HEIGHT="${OPENCLAW_BROWSER_HEIGHT:-1080}"
OPENCLAW_BROWSER_HEADLESS="${OPENCLAW_BROWSER_HEADLESS:-false}"
OPENCLAW_BROWSER_DEBUG_PORT="${OPENCLAW_BROWSER_DEBUG_PORT:-18800}"
OPENCLAW_VNC_PORT="${OPENCLAW_VNC_PORT:-5900}"
CHROME_BIN="${CHROME_BIN:-/usr/bin/chromium}"
OPENCLAW_MODEL_FALLBACKS="${OPENCLAW_MODEL_FALLBACKS:-[\"openai/gpt-5.3-codex\",\"openai/gpt-5.4\"]}"
OPENCLAW_MODEL_PRIMARY="${OPENCLAW_MODEL_PRIMARY:-anthropic/claude-opus-4-6}"

# Clean up stale Chromium profile locks from previous container runs.
# force-recreate gives the container a new hostname, so Chromium sees the
# old lock as belonging to "another computer" and refuses to start.
find "$OPENCLAW_STATE_DIR/browser" -name 'SingletonLock' -delete 2>/dev/null || true
find "$OPENCLAW_STATE_DIR/browser" -name 'SingletonSocket' -delete 2>/dev/null || true
find "$OPENCLAW_STATE_DIR/browser" -name 'SingletonCookie' -delete 2>/dev/null || true

mkdir -p "$OPENCLAW_STATE_DIR" "$OPENCLAW_BROWSER_DOWNLOADS_DIR" /opt/repos
# Only chown container-internal dirs — NOT bind-mounted /opt/repos
chown -R node:node "$OPENCLAW_STATE_DIR" "$OPENCLAW_BROWSER_DOWNLOADS_DIR" /home/node
touch /home/node/.gitconfig
chown node:node /home/node/.gitconfig

if [[ -n "${GIT_AUTHOR_NAME:-}" ]]; then
  gosu node git config --global user.name "$GIT_AUTHOR_NAME"
fi
if [[ -n "${GIT_AUTHOR_EMAIL:-}" ]]; then
  gosu node git config --global user.email "$GIT_AUTHOR_EMAIL"
fi
export GIT_COMMITTER_NAME="${GIT_COMMITTER_NAME:-${GIT_AUTHOR_NAME:-}}"
export GIT_COMMITTER_EMAIL="${GIT_COMMITTER_EMAIL:-${GIT_AUTHOR_EMAIL:-}}"

start_display_stack() {
  export DISPLAY=:99

  # Clean up stale X server lock files from previous runs
  rm -f /tmp/.X99-lock /tmp/.X11-unix/X99

  # Start virtual X server
  Xvfb :99 -screen 0 "${OPENCLAW_BROWSER_WIDTH}x${OPENCLAW_BROWSER_HEIGHT}x24" -ac -nolisten tcp >/tmp/xvfb.log 2>&1 &

  # Wait for Xvfb to fully initialize before starting dependent services
  sleep 2

  # Start window manager and VNC server (both depend on Xvfb being ready)
  fluxbox >/tmp/fluxbox.log 2>&1 &
  x11vnc -display :99 -forever -shared -rfbport "$OPENCLAW_VNC_PORT" -nopw >/tmp/x11vnc.log 2>&1 &
}

# Auto-configure on fresh install (no openclaw.json yet)
if [[ ! -f "$OPENCLAW_STATE_DIR/openclaw.json" ]]; then
  gosu node openclaw config set gateway.mode local 2>/dev/null || true
  gosu node openclaw config set gateway.bind lan 2>/dev/null || true
fi

case "$mode" in
  gateway)
    start_display_stack
    exec gosu node openclaw gateway
    ;;
  shell)
    start_display_stack
    exec gosu node /bin/bash "$@"
    ;;
  *)
    start_display_stack
    exec gosu node "$mode" "$@"
    ;;
esac
