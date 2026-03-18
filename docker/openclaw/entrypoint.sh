#!/usr/bin/env bash
set -euo pipefail

mode="${1:-gateway}"
if [[ $# -gt 0 ]]; then
  shift
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

mkdir -p "$OPENCLAW_STATE_DIR" "$OPENCLAW_BROWSER_DOWNLOADS_DIR" /opt/repos
chown -R node:node "$OPENCLAW_STATE_DIR" "$OPENCLAW_BROWSER_DOWNLOADS_DIR" /opt/repos
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

seed_auth_if_present() {
  local anthropic_setup_token="${OPENCLAW_ANTHROPIC_SETUP_TOKEN:-}"

  if [[ -n "$anthropic_setup_token" ]]; then
    printf '%s\n' "$anthropic_setup_token" | gosu node openclaw models auth paste-token --provider anthropic >/dev/null 2>&1 || true
  fi
}

case "$mode" in
  gateway)
    start_display_stack
    seed_auth_if_present
    exec gosu node openclaw gateway
    ;;
  shell)
    start_display_stack
    seed_auth_if_present
    exec gosu node /bin/bash "$@"
    ;;
  *)
    start_display_stack
    seed_auth_if_present
    exec gosu node "$mode" "$@"
    ;;
esac
