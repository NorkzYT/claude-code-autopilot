#!/usr/bin/env bash
# chromium-wrapper.sh — transparent Chromium intercept for browser isolation
#
# Installed as /usr/bin/chromium (the real binary is moved to /usr/bin/chromium.real).
#
# Behavior depends on OPENCLAW_BROWSER_ISOLATION:
#   "per-agent"       → allocate a per-agent display, profile, and CDP port
#   "shared" / unset  → pass through to chromium.real unchanged (current behavior)
#
# Per-agent mode reads OPENCLAW_AGENT_ID (set by OpenClaw for each agent run)
# and calls browser-manager to allocate resources.

set -euo pipefail

REAL_CHROMIUM="/usr/bin/chromium.real"
ISOLATION="${OPENCLAW_BROWSER_ISOLATION:-shared}"
AGENT_ID="${OPENCLAW_AGENT_ID:-}"

# ── Shared mode (default): pass through unchanged ──────────────────────────
if [[ "$ISOLATION" != "per-agent" ]] || [[ -z "$AGENT_ID" ]]; then
  exec "$REAL_CHROMIUM" "$@"
fi

# ── Per-agent mode: allocate display + profile + CDP port ──────────────────
alloc_output="$(browser-manager allocate "$AGENT_ID")"
if [[ $? -ne 0 ]]; then
  echo "chromium-wrapper: failed to allocate browser resources for agent '$AGENT_ID'" >&2
  echo "$alloc_output" >&2
  exit 1
fi

# Parse output: DISPLAY=:100 CDP_PORT=18801 PROFILE_DIR=/path/to/profile
eval "$alloc_output"

# Build modified argument list:
#   - Set DISPLAY for this agent's X server
#   - Override --user-data-dir to isolate profile
#   - Override --remote-debugging-port to avoid conflicts
#
# Strip any existing --user-data-dir or --remote-debugging-port from caller args
filtered_args=()
for arg in "$@"; do
  case "$arg" in
    --user-data-dir=*)          ;; # strip
    --remote-debugging-port=*)  ;; # strip
    *) filtered_args+=("$arg")  ;;
  esac
done

export DISPLAY
exec "$REAL_CHROMIUM" \
  --user-data-dir="$PROFILE_DIR" \
  --remote-debugging-port="$CDP_PORT" \
  "${filtered_args[@]}"
