#!/usr/bin/env bash
#
# ralph-docker.sh — Docker sandbox wrapper for Ralph iterations.
#
# Runs a single Ralph iteration inside a Docker container for isolation.
# No network access by default. Workspace mounted read-write.
#
# Usage:
#   ralph-docker.sh --workspace DIR --prd PATH [--progress PATH] [--allow-network]
#
# Environment:
#   RALPH_PERMISSION_MODE  — Claude permission mode (default: acceptEdits)
#   RALPH_MODEL            — Claude model to use (optional)
#   RALPH_COMPOSE_FILE     — Path to docker-compose file (default: auto-detect)
#

set -euo pipefail

# --- Defaults ---
WORKSPACE=""
PRD_PATH=""
PROGRESS_PATH=""
ALLOW_NETWORK=false

# --- Parse args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace|-w)      WORKSPACE="$2"; shift 2 ;;
    --prd|-p)            PRD_PATH="$2"; shift 2 ;;
    --progress)          PROGRESS_PATH="$2"; shift 2 ;;
    --allow-network)     ALLOW_NETWORK=true; shift ;;
    --help|-h)
      echo "Usage: ralph-docker.sh --workspace DIR --prd PATH [--progress PATH] [--allow-network]"
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$WORKSPACE" || -z "$PRD_PATH" ]]; then
  echo "ERROR: --workspace and --prd are required" >&2
  exit 1
fi

# Resolve paths
WORKSPACE="$(cd "$WORKSPACE" && pwd)"
if [[ ! "$PRD_PATH" = /* ]]; then
  PRD_PATH="$WORKSPACE/$PRD_PATH"
fi
PROGRESS_PATH="${PROGRESS_PATH:-$(dirname "$PRD_PATH")/progress.txt}"

# --- Locate compose file ---
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE_FILE="${RALPH_COMPOSE_FILE:-$REPO_ROOT/docker-compose.ralph.yml}"

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "ERROR: docker-compose.ralph.yml not found at: $COMPOSE_FILE" >&2
  echo "Run from the repo root or set RALPH_COMPOSE_FILE." >&2
  exit 1
fi

# --- Unique project name per workspace (allows parallel runs across repos) ---
# Hash the workspace path to get a short unique suffix
WORKSPACE_HASH=$(echo -n "$WORKSPACE" | md5sum | cut -c1-8)
export RALPH_PROJECT_NAME="ralph-${WORKSPACE_HASH}"

# --- Build image if needed ---
echo "[ralph-docker] Building sandbox image (cached)..."
echo "[ralph-docker] Project: $RALPH_PROJECT_NAME (workspace: $WORKSPACE)"
docker compose -f "$COMPOSE_FILE" build --quiet ralph 2>/dev/null || \
  docker compose -f "$COMPOSE_FILE" build ralph

# --- Compute relative paths for container ---
# PRD and progress paths must be relative to workspace for container mounting
REL_PRD="${PRD_PATH#$WORKSPACE/}"
REL_PROGRESS="${PROGRESS_PATH#$WORKSPACE/}"

# --- Build prompt (same as ralph-once.sh) ---
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
PROMPT="@/workspace/${REL_PRD} @/workspace/${REL_PROGRESS}

Read the PRD and progress file carefully.

1. Identify the next incomplete task from the PRD task queue.
2. Implement ONLY that one task — nothing else.
3. Run any tests and type checks specified in the PRD validation section.
4. Append an iteration entry to /workspace/${REL_PROGRESS} with this exact format:

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
- Follow the project's existing code style and patterns."

# --- Set up environment ---
PERMISSION_MODE="${RALPH_PERMISSION_MODE:-acceptEdits}"
DOCKER_ENV=(
  -e "CLAUDE_PROJECT_DIR=/workspace"
)

if [[ -n "${RALPH_MODEL:-}" ]]; then
  DOCKER_ENV+=(-e "RALPH_MODEL=$RALPH_MODEL")
fi

# --- Network mode ---
NETWORK_OVERRIDE=()
if [[ "$ALLOW_NETWORK" == "true" ]]; then
  NETWORK_OVERRIDE=(--network default)
fi

# --- Git config for commit attribution ---
GIT_USER_NAME=$(git config --global user.name 2>/dev/null || echo "Ralph Bot")
GIT_USER_EMAIL=$(git config --global user.email 2>/dev/null || echo "ralph@localhost")

# --- Run container ---
echo "[ralph-docker] Running iteration in sandbox..."
STDOUT_FILE=$(mktemp)
EXIT_CODE=0

WORKSPACE="$WORKSPACE" docker compose -f "$COMPOSE_FILE" run --rm \
  "${NETWORK_OVERRIDE[@]}" \
  "${DOCKER_ENV[@]}" \
  -e "GIT_USER_NAME=$GIT_USER_NAME" \
  -e "GIT_USER_EMAIL=$GIT_USER_EMAIL" \
  ralph \
  claude --permission-mode "$PERMISSION_MODE" -p "$PROMPT" \
  > "$STDOUT_FILE" 2>&1 || EXIT_CODE=$?

OUTPUT=$(cat "$STDOUT_FILE")
rm -f "$STDOUT_FILE"

# --- Check for completion ---
if echo "$OUTPUT" | grep -qiE '<promise>COMPLETE</promise>'; then
  echo "[ralph-docker] PRD COMPLETE — promise detected"
  exit 0
fi

if [[ -z "$OUTPUT" ]] || echo "$OUTPUT" | grep -qi "no messages returned"; then
  echo "[ralph-docker] WARNING: Empty or 'no messages returned'" >&2
  exit 1
fi

echo "[ralph-docker] Iteration done — more work needed"
exit 1
