#!/usr/bin/env bash
# browser-manager.sh — per-agent display allocation & lifecycle
#
# Subcommands:
#   allocate <agent-id>   Assign a display + CDP port to an agent
#   release  <agent-id>   Free the agent's display and stop its Xvfb
#   cleanup               Release all agent displays (shutdown hook)
#
# Display mapping:
#   :99         → shared viewer/manual session (always running, not managed here)
#   :100–:119   → agent-allocated displays (CDP ports 18801–18820)
#
# Lock files live at $OPENCLAW_STATE_DIR/display-locks/<display-number>
# Each lock file contains the owning agent ID.

set -euo pipefail

OPENCLAW_STATE_DIR="${OPENCLAW_STATE_DIR:-/home/node/.openclaw}"
LOCK_DIR="$OPENCLAW_STATE_DIR/display-locks"
PROFILE_DIR="$OPENCLAW_STATE_DIR/browser-profiles"
BROWSER_WIDTH="${OPENCLAW_BROWSER_WIDTH:-1920}"
BROWSER_HEIGHT="${OPENCLAW_BROWSER_HEIGHT:-1080}"

MIN_DISPLAY=100
MAX_DISPLAY=119
CDP_PORT_BASE=18801   # display :100 → port 18801, :101 → 18802, etc.

mkdir -p "$LOCK_DIR" "$PROFILE_DIR"

# ---------------------------------------------------------------------------
# allocate <agent-id>
#   Prints: DISPLAY=:<N> CDP_PORT=<P> PROFILE_DIR=<path>
# ---------------------------------------------------------------------------
cmd_allocate() {
  local agent_id="${1:?Usage: browser-manager allocate <agent-id>}"

  # Re-use existing allocation for this agent
  for lock_file in "$LOCK_DIR"/*; do
    [[ -f "$lock_file" ]] || continue
    if [[ "$(cat "$lock_file")" == "$agent_id" ]]; then
      local display
      display="$(basename "$lock_file")"
      local cdp_port=$(( CDP_PORT_BASE + display - MIN_DISPLAY ))
      echo "DISPLAY=:${display} CDP_PORT=${cdp_port} PROFILE_DIR=${PROFILE_DIR}/${agent_id}"
      return 0
    fi
  done

  # Find next free display
  for (( d=MIN_DISPLAY; d<=MAX_DISPLAY; d++ )); do
    local lock_file="$LOCK_DIR/$d"
    # Atomic lock: create file only if it doesn't exist
    if ( set -o noclobber; echo "$agent_id" > "$lock_file" ) 2>/dev/null; then
      local cdp_port=$(( CDP_PORT_BASE + d - MIN_DISPLAY ))
      local profile="$PROFILE_DIR/$agent_id"
      mkdir -p "$profile"

      # Clean stale X lock from previous container runs
      rm -f "/tmp/.X${d}-lock" "/tmp/.X11-unix/X${d}"

      # Start Xvfb for this display
      Xvfb ":$d" -screen 0 "${BROWSER_WIDTH}x${BROWSER_HEIGHT}x24" \
        -ac -nolisten tcp >/tmp/xvfb-${d}.log 2>&1 &

      # Brief wait for Xvfb to initialize
      sleep 1

      echo "DISPLAY=:${d} CDP_PORT=${cdp_port} PROFILE_DIR=${profile}"
      return 0
    fi
  done

  echo "ERROR: No free displays (all ${MIN_DISPLAY}–${MAX_DISPLAY} in use)" >&2
  return 1
}

# ---------------------------------------------------------------------------
# release <agent-id>
# ---------------------------------------------------------------------------
cmd_release() {
  local agent_id="${1:?Usage: browser-manager release <agent-id>}"

  for lock_file in "$LOCK_DIR"/*; do
    [[ -f "$lock_file" ]] || continue
    if [[ "$(cat "$lock_file")" == "$agent_id" ]]; then
      local display
      display="$(basename "$lock_file")"

      # Kill the Xvfb for this display
      local xvfb_pid
      xvfb_pid="$(pgrep -f "Xvfb :${display} " 2>/dev/null || true)"
      if [[ -n "$xvfb_pid" ]]; then
        kill "$xvfb_pid" 2>/dev/null || true
      fi

      rm -f "$lock_file"
      rm -f "/tmp/.X${display}-lock" "/tmp/.X11-unix/X${display}"
      return 0
    fi
  done

  # Agent not found — nothing to release
  return 0
}

# ---------------------------------------------------------------------------
# cleanup — release ALL agent displays (container shutdown hook)
# ---------------------------------------------------------------------------
cmd_cleanup() {
  for lock_file in "$LOCK_DIR"/*; do
    [[ -f "$lock_file" ]] || continue
    local agent_id
    agent_id="$(cat "$lock_file")"
    cmd_release "$agent_id"
  done
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
case "${1:-}" in
  allocate) cmd_allocate "${2:-}" ;;
  release)  cmd_release  "${2:-}" ;;
  cleanup)  cmd_cleanup            ;;
  *)
    echo "Usage: browser-manager {allocate|release|cleanup} [agent-id]" >&2
    exit 1
    ;;
esac
