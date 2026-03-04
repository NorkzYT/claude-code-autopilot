#!/usr/bin/env bash
#
# ralph-once.sh — Single iteration of Multi-Session Ralph.
#
# Runs one fresh `claude -p` session against a PRD + progress file.
# The agent reads the PRD, finds the next incomplete task, implements it,
# runs tests, updates progress.txt, and commits.
#
# Usage:
#   ralph-once.sh <workspace> <prd_path> [progress_path]
#
# Exit codes:
#   0 — PRD is complete (<promise>COMPLETE</promise> detected)
#   1 — More work needed (or error)
#
# Environment:
#   RALPH_PERMISSION_MODE  — Claude permission mode (default: acceptEdits)
#   RALPH_MODEL            — Claude model to use (optional)
#   RALPH_LOG              — Log file path (default: .claude/logs/ralph-external.log)
#

set -euo pipefail

# --- Args ---
WORKSPACE="${1:?Usage: ralph-once.sh <workspace> <prd_path> [progress_path]}"
PRD_PATH="${2:?Usage: ralph-once.sh <workspace> <prd_path> [progress_path]}"
PROGRESS_PATH="${3:-$(dirname "$PRD_PATH")/progress.txt}"

PERMISSION_MODE="${RALPH_PERMISSION_MODE:-acceptEdits}"
LOG_FILE="${RALPH_LOG:-$WORKSPACE/.claude/logs/ralph-external.log}"

# --- Ensure files exist ---
if [[ ! -f "$PRD_PATH" ]]; then
  echo "ERROR: PRD file not found: $PRD_PATH" >&2
  exit 1
fi

# Create progress file if it doesn't exist
if [[ ! -f "$PROGRESS_PATH" ]]; then
  echo "# Progress — $(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$PROGRESS_PATH"
  echo "" >> "$PROGRESS_PATH"
  echo "No iterations completed yet." >> "$PROGRESS_PATH"
fi

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# --- Build prompt ---
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
PROMPT="@${PRD_PATH} @${PROGRESS_PATH}

Read the PRD and progress file carefully.

1. Identify the next incomplete task from the PRD task queue.
2. Implement ONLY that one task — nothing else.
3. Run any tests and type checks specified in the PRD validation section.
4. Append an iteration entry to ${PROGRESS_PATH} with this exact format:

=== Iteration N (${TIMESTAMP}) ===
Task: <what you worked on>
Done:
- <what you accomplished>
Files changed: <list of files>
Commit: <commit hash>
Next: <what should be done next, or NONE if PRD is complete>

5. Commit your changes with a descriptive message.

IMPORTANT:
- ONLY DO ONE TASK AT A TIME.
- If ALL tasks in the PRD are already complete, output <promise>COMPLETE</promise> and stop.
- Do NOT skip tasks or combine multiple tasks.
- Follow the project's existing code style and patterns.
- Refer to CLAUDE.md for repo conventions."

# --- Build claude command ---
CLAUDE_CMD=(claude --permission-mode "$PERMISSION_MODE" -p "$PROMPT")

if [[ -n "${RALPH_MODEL:-}" ]]; then
  CLAUDE_CMD+=(--model "$RALPH_MODEL")
fi

# --- Run iteration ---
echo "[ralph-once] Starting iteration at $TIMESTAMP" | tee -a "$LOG_FILE"
echo "[ralph-once] PRD: $PRD_PATH" | tee -a "$LOG_FILE"
echo "[ralph-once] Progress: $PROGRESS_PATH" | tee -a "$LOG_FILE"

STDOUT_FILE=$(mktemp)
EXIT_CODE=0

cd "$WORKSPACE"

if "${CLAUDE_CMD[@]}" > "$STDOUT_FILE" 2>>"$LOG_FILE"; then
  echo "[ralph-once] Claude session completed successfully" >> "$LOG_FILE"
else
  EXIT_CODE=$?
  echo "[ralph-once] Claude session exited with code $EXIT_CODE" >> "$LOG_FILE"
fi

# --- Check for completion promise ---
OUTPUT=$(cat "$STDOUT_FILE")
rm -f "$STDOUT_FILE"

if echo "$OUTPUT" | grep -qiE '<promise>COMPLETE</promise>'; then
  echo "[ralph-once] PRD COMPLETE — promise detected" | tee -a "$LOG_FILE"
  exit 0
fi

# Check for "No messages returned" bug (Claude CLI quirk)
if [[ -z "$OUTPUT" ]] || echo "$OUTPUT" | grep -qi "no messages returned"; then
  echo "[ralph-once] WARNING: Empty or 'no messages returned' — treating as transient error" >> "$LOG_FILE"
  exit 1
fi

echo "[ralph-once] Iteration done — more work needed" >> "$LOG_FILE"
exit 1
