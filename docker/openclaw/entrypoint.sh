#!/usr/bin/env bash
set -euo pipefail

mode="${1:-gateway}"
if [[ $# -gt 0 ]]; then
  shift
fi

OPENCLAW_STATE_DIR="${OPENCLAW_STATE_DIR:-/home/openclaw/.openclaw}"
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

if [[ -n "${GIT_AUTHOR_NAME:-}" ]]; then
  git config --global user.name "$GIT_AUTHOR_NAME"
fi
if [[ -n "${GIT_AUTHOR_EMAIL:-}" ]]; then
  git config --global user.email "$GIT_AUTHOR_EMAIL"
fi
export GIT_COMMITTER_NAME="${GIT_COMMITTER_NAME:-${GIT_AUTHOR_NAME:-}}"
export GIT_COMMITTER_EMAIL="${GIT_COMMITTER_EMAIL:-${GIT_AUTHOR_EMAIL:-}}"

start_display_stack() {
  export DISPLAY=:99
  Xvfb :99 -screen 0 "${OPENCLAW_BROWSER_WIDTH}x${OPENCLAW_BROWSER_HEIGHT}x24" -ac -nolisten tcp >/tmp/xvfb.log 2>&1 &
  fluxbox >/tmp/fluxbox.log 2>&1 &
  x11vnc -display :99 -forever -shared -rfbport "$OPENCLAW_VNC_PORT" -nopw >/tmp/x11vnc.log 2>&1 &
}

configure_openclaw() {
  local thinking_default="${OPENCLAW_THINKING_DEFAULT:-}"

  if [[ -z "$thinking_default" && "$OPENCLAW_MODEL_PRIMARY" == "anthropic/claude-sonnet-4-6" ]]; then
    thinking_default="high"
  fi

  openclaw config set gateway.mode local >/dev/null 2>&1 || true
  openclaw config set gateway.port "${OPENCLAW_GATEWAY_PORT:-18789}" >/dev/null 2>&1 || true
  openclaw config set gateway.bind "${OPENCLAW_GATEWAY_BIND:-all}" >/dev/null 2>&1 || true
  openclaw config set browser.enabled true >/dev/null 2>&1 || true
  openclaw config set browser.headless "$OPENCLAW_BROWSER_HEADLESS" >/dev/null 2>&1 || true
  openclaw config set browser.noSandbox true >/dev/null 2>&1 || true
  openclaw config set browser.executablePath "$CHROME_BIN" >/dev/null 2>&1 || true
  openclaw config set browser.downloads.directory "$OPENCLAW_BROWSER_DOWNLOADS_DIR" >/dev/null 2>&1 || true
  openclaw config set agents.defaults.model.primary "$OPENCLAW_MODEL_PRIMARY" >/dev/null 2>&1 || true
  openclaw config set agents.defaults.model.fallbacks "$OPENCLAW_MODEL_FALLBACKS" --json >/dev/null 2>&1 || true
  if [[ -n "$thinking_default" ]]; then
    openclaw config set agents.defaults.thinkingDefault "$thinking_default" >/dev/null 2>&1 || true
  fi
}

seed_auth_if_present() {
  local anthropic_setup_token="${OPENCLAW_ANTHROPIC_SETUP_TOKEN:-}"

  if [[ -n "$anthropic_setup_token" ]]; then
    printf '%s\n' "$anthropic_setup_token" | openclaw models auth paste-token --provider anthropic >/dev/null 2>&1 || true
  fi
}

case "$mode" in
  gateway)
    start_display_stack
    configure_openclaw
    seed_auth_if_present
    openclaw gateway start
    exec openclaw gateway logs --follow
    ;;
  shell)
    start_display_stack
    configure_openclaw
    seed_auth_if_present
    exec /bin/bash "$@"
    ;;
  *)
    start_display_stack
    configure_openclaw
    seed_auth_if_present
    exec "$mode" "$@"
    ;;
esac
