#!/usr/bin/env bash
#
# afk-ralph.sh — Full AFK Multi-Session Ralph loop.
#
# Runs ralph-once.sh in a loop, starting a fresh Claude session per iteration.
# Each iteration reads the PRD + progress file, does ONE task, commits, and exits.
# Fresh sessions prevent context rot.
#
# Usage:
#   afk-ralph.sh [--iterations N] [--workspace DIR] [--prd PATH] [--docker]
#
# Examples:
#   afk-ralph.sh --prd ./PRD.md
#   afk-ralph.sh --iterations 10 --prd .claude/context/api/PRD.md
#   afk-ralph.sh --iterations 20 --prd ./PRD.md --docker
#
# Environment:
#   RALPH_PERMISSION_MODE  — Claude permission mode (default: acceptEdits)
#   RALPH_MODEL            — Claude model to use (optional)
#   RALPH_NOTIFY           — Enable notifications: 1/true (default: 1)
#

set -euo pipefail

# --- Defaults ---
MAX_ITERATIONS=20
WORKSPACE="$(pwd)"
PRD_PATH=""
USE_DOCKER=false
RETRY_DELAY=5
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NOTIFY="${RALPH_NOTIFY:-1}"

# --- Parse args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --iterations|-n) MAX_ITERATIONS="$2"; shift 2 ;;
    --workspace|-w)  WORKSPACE="$2"; shift 2 ;;
    --prd|-p)        PRD_PATH="$2"; shift 2 ;;
    --docker|-d)     USE_DOCKER=true; shift ;;
    --help|-h)
      echo "Usage: afk-ralph.sh [--iterations N] [--workspace DIR] [--prd PATH] [--docker]"
      echo ""
      echo "Options:"
      echo "  --iterations, -n  Max iterations (default: 20)"
      echo "  --workspace, -w   Workspace directory (default: cwd)"
      echo "  --prd, -p         Path to PRD file (required)"
      echo "  --docker, -d      Run each iteration in Docker sandbox"
      echo "  --help, -h        Show this help"
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$PRD_PATH" ]]; then
  echo "ERROR: --prd is required" >&2
  exit 1
fi

# Resolve paths
WORKSPACE="$(cd "$WORKSPACE" && pwd)"
if [[ ! "$PRD_PATH" = /* ]]; then
  PRD_PATH="$WORKSPACE/$PRD_PATH"
fi
PROGRESS_PATH="$(dirname "$PRD_PATH")/progress.txt"
LOG_FILE="$WORKSPACE/.claude/logs/ralph-external.log"

mkdir -p "$(dirname "$LOG_FILE")"

# --- Notification helper ---
notify() {
  local title="$1"
  local body="$2"
  if [[ "$NOTIFY" == "1" || "$NOTIFY" == "true" ]]; then
    # Use the project's notify_linux.py if available
    local notify_script="$WORKSPACE/.claude/hooks/notify_linux.py"
    if [[ -f "$notify_script" ]]; then
      echo "{\"notification_type\":\"idle_prompt\",\"message\":\"$body\"}" | \
        CLAUDE_PROJECT_DIR="$WORKSPACE" python3 "$notify_script" 2>/dev/null || true
    fi
  fi
}

# --- Ctrl+C handler ---
cleanup() {
  echo ""
  echo "[afk-ralph] Interrupted at iteration $i/$MAX_ITERATIONS"
  echo "[afk-ralph] Progress saved in: $PROGRESS_PATH"
  echo "[afk-ralph] Log: $LOG_FILE"

  TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  echo "" >> "$PROGRESS_PATH"
  echo "=== INTERRUPTED ($TIMESTAMP) ===" >> "$PROGRESS_PATH"
  echo "Loop cancelled by user at iteration $i/$MAX_ITERATIONS" >> "$PROGRESS_PATH"

  notify "Ralph Loop Cancelled" "Stopped at iteration $i/$MAX_ITERATIONS"
  exit 130
}
trap cleanup INT TERM

# --- Logging ---
echo "============================================" >> "$LOG_FILE"
echo "[afk-ralph] Starting AFK Ralph loop" >> "$LOG_FILE"
echo "[afk-ralph] Max iterations: $MAX_ITERATIONS" >> "$LOG_FILE"
echo "[afk-ralph] Workspace: $WORKSPACE" >> "$LOG_FILE"
echo "[afk-ralph] PRD: $PRD_PATH" >> "$LOG_FILE"
echo "[afk-ralph] Docker: $USE_DOCKER" >> "$LOG_FILE"
echo "[afk-ralph] Started: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$LOG_FILE"
echo "============================================" >> "$LOG_FILE"

echo "AFK Ralph Loop"
echo "  PRD:        $PRD_PATH"
echo "  Progress:   $PROGRESS_PATH"
echo "  Iterations: $MAX_ITERATIONS"
echo "  Docker:     $USE_DOCKER"
echo "  Log:        $LOG_FILE"
echo ""

# --- Main loop ---
CONSECUTIVE_ERRORS=0
MAX_CONSECUTIVE_ERRORS=3

for (( i=1; i<=MAX_ITERATIONS; i++ )); do
  echo "--- Iteration $i/$MAX_ITERATIONS $(date -u +%H:%M:%S) ---"

  ITER_EXIT=0

  if [[ "$USE_DOCKER" == "true" ]]; then
    # Run iteration in Docker sandbox
    "$SCRIPT_DIR/ralph-docker.sh" \
      --workspace "$WORKSPACE" \
      --prd "$PRD_PATH" \
      --progress "$PROGRESS_PATH" \
      || ITER_EXIT=$?
  else
    # Run iteration directly
    RALPH_LOG="$LOG_FILE" \
    "$SCRIPT_DIR/ralph-once.sh" \
      "$WORKSPACE" \
      "$PRD_PATH" \
      "$PROGRESS_PATH" \
      || ITER_EXIT=$?
  fi

  if [[ $ITER_EXIT -eq 0 ]]; then
    # Completion promise detected
    echo ""
    echo "PRD COMPLETE after $i iteration(s)!"
    echo "[afk-ralph] PRD complete after $i iterations" >> "$LOG_FILE"
    notify "Ralph Loop Complete" "PRD finished in $i iterations"
    exit 0
  fi

  # Check for consecutive errors
  if [[ $ITER_EXIT -gt 1 ]]; then
    CONSECUTIVE_ERRORS=$((CONSECUTIVE_ERRORS + 1))
    echo "[afk-ralph] Error in iteration $i (consecutive: $CONSECUTIVE_ERRORS)" >> "$LOG_FILE"

    if [[ $CONSECUTIVE_ERRORS -ge $MAX_CONSECUTIVE_ERRORS ]]; then
      echo ""
      echo "ERROR: $MAX_CONSECUTIVE_ERRORS consecutive errors. Stopping."
      echo "[afk-ralph] Stopping after $MAX_CONSECUTIVE_ERRORS consecutive errors" >> "$LOG_FILE"
      notify "Ralph Loop Failed" "Stopped after $MAX_CONSECUTIVE_ERRORS consecutive errors at iteration $i"
      exit 1
    fi

    echo "  Error detected — waiting ${RETRY_DELAY}s before retry..."
    sleep "$RETRY_DELAY"
  else
    CONSECUTIVE_ERRORS=0
  fi

  # Brief pause between iterations to avoid rate limits
  if [[ $i -lt $MAX_ITERATIONS ]]; then
    sleep 2
  fi
done

echo ""
echo "Reached max iterations ($MAX_ITERATIONS) without PRD completion."
echo "[afk-ralph] Reached max iterations ($MAX_ITERATIONS)" >> "$LOG_FILE"
notify "Ralph Loop: Max Iterations" "Reached $MAX_ITERATIONS iterations without completion"
exit 1
