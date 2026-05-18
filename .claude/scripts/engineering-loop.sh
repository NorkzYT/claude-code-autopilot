#!/usr/bin/env bash
#
# engineering-loop.sh — Autonomous engineering driver.
#
# Reads a tasks file (markdown) and executes each pending task through a fresh
# `claude -p` session. Optionally generates a PRD per task via the local CrewAI
# engineering planner (`--use-planner`). After each session, attempts a test
# run; on failure, retries up to --max-retries times with the prior test output
# attached as additional context.
#
# Usage:
#   engineering-loop.sh [OPTIONS] <tasks-file>
#
# Options:
#   --workspace DIR      Repo to work in (default: cwd)
#   --use-planner        Run CrewAI planner before each task to generate a PRD
#   --max-retries N      Max claude -p retries per task on test failure (default: 3)
#   --model MODEL        Claude model override (passed to --model)
#   --dry-run            Parse tasks and print what would run, no execution
#   -h, --help           Show this help
#
# Task file format (markdown):
#
#   ## Task: <slug>
#   **Status:** pending
#   **Branch:** feat/<slug>          # optional; default is feat/<slug>
#
#   <free-form task description>
#
#   ---
#
# Status values: pending | in-progress | done | failed
#
# Environment:
#   ENG_PERMISSION_MODE  — Claude permission mode (default: acceptEdits)
#

set -euo pipefail

# --- Defaults ---
WORKSPACE="$(pwd)"
USE_PLANNER=0
MAX_RETRIES=3
MODEL=""
DRY_RUN=0
TASKS_FILE=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PERMISSION_MODE="${ENG_PERMISSION_MODE:-acceptEdits}"

usage() {
  sed -n '3,36p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# --- Parse args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace) WORKSPACE="$2"; shift 2 ;;
    --use-planner) USE_PLANNER=1; shift ;;
    --max-retries) MAX_RETRIES="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; TASKS_FILE="${1:-}"; shift || true ;;
    -*) echo "ERROR: unknown option: $1" >&2; exit 2 ;;
    *)
      if [[ -z "$TASKS_FILE" ]]; then
        TASKS_FILE="$1"
        shift
      else
        echo "ERROR: unexpected positional arg: $1" >&2
        exit 2
      fi
      ;;
  esac
done

if [[ -z "$TASKS_FILE" ]]; then
  echo "ERROR: <tasks-file> is required" >&2
  usage
  exit 2
fi

# Resolve paths
WORKSPACE="$(cd "$WORKSPACE" && pwd)"
if [[ ! "$TASKS_FILE" = /* ]]; then
  TASKS_FILE="$WORKSPACE/$TASKS_FILE"
fi

if [[ ! -f "$TASKS_FILE" ]]; then
  echo "ERROR: tasks file not found: $TASKS_FILE" >&2
  exit 1
fi

if ! [[ "$MAX_RETRIES" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --max-retries must be a non-negative integer" >&2
  exit 2
fi

LOG_FILE="$WORKSPACE/.claude/logs/engineering-loop.log"
mkdir -p "$(dirname "$LOG_FILE")"

log() {
  printf '[engineering-loop] %s\n' "$*" | tee -a "$LOG_FILE"
}

# --- Parse tasks ----------------------------------------------------------
# Emits one record per task on stdout, with fields separated by a literal tab:
#   <slug>\t<status>\t<branch>\t<description-base64>
#
# Description is base64-encoded so embedded newlines pass through cleanly.
parse_tasks() {
  python3 - "$TASKS_FILE" <<'PY'
import base64
import re
import sys
from pathlib import Path

src = Path(sys.argv[1]).read_text(encoding="utf-8")

# Split on lines that start with "## Task:" header
blocks = re.split(r"(?m)^(?=## Task:\s*)", src)
for block in blocks:
    if not block.strip().startswith("## Task:"):
        continue

    # Strip a trailing "---" separator if present
    block = re.sub(r"(?m)^---\s*$", "", block).rstrip()

    lines = block.splitlines()
    header = lines[0]
    m = re.match(r"^##\s+Task:\s*(.+?)\s*$", header)
    if not m:
        continue
    slug = m.group(1).strip()
    if not slug:
        continue

    status = "pending"
    branch = f"feat/{slug}"
    desc_lines = []
    in_meta = True
    for raw in lines[1:]:
        line = raw.rstrip()
        stripped = line.strip()
        if in_meta:
            sm = re.match(r"^\*\*Status:\*\*\s*(\S+)\s*$", stripped)
            if sm:
                status = sm.group(1).strip().lower()
                continue
            bm = re.match(r"^\*\*Branch:\*\*\s*(\S+)\s*$", stripped)
            if bm:
                branch = bm.group(1).strip()
                continue
            if stripped == "":
                # blank line separates metadata from description; description starts after
                in_meta = False
                continue
            # Any non-meta line ends the meta block
            in_meta = False
            desc_lines.append(line)
        else:
            desc_lines.append(line)

    description = "\n".join(desc_lines).strip()
    enc = base64.b64encode(description.encode("utf-8")).decode("ascii")
    sys.stdout.write(f"{slug}\t{status}\t{branch}\t{enc}\n")
PY
}

# --- Update task status atomically ---------------------------------------
# Args: <slug> <new_status>
update_task_status() {
  local slug="$1"
  local new_status="$2"
  python3 - "$TASKS_FILE" "$slug" "$new_status" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
target_slug = sys.argv[2]
new_status = sys.argv[3]

src = path.read_text(encoding="utf-8")
blocks = re.split(r"(?m)^(?=## Task:\s*)", src)

out_parts = []
for block in blocks:
    header_m = re.match(r"^##\s+Task:\s*(.+?)\s*$", block.splitlines()[0]) if block.strip().startswith("## Task:") else None
    if header_m and header_m.group(1).strip() == target_slug:
        new_block, n = re.subn(
            r"(?m)^(\*\*Status:\*\*\s*)\S+\s*$",
            rf"\1{new_status}",
            block,
            count=1,
        )
        if n == 0:
            # Inject a Status line right after the header if missing
            lines = block.splitlines()
            lines.insert(1, f"**Status:** {new_status}")
            new_block = "\n".join(lines)
            if not new_block.endswith("\n"):
                new_block += "\n"
        out_parts.append(new_block)
    else:
        out_parts.append(block)

path.write_text("".join(out_parts), encoding="utf-8")
PY
}

# --- Test command detection ---------------------------------------------
detect_test_command() {
  local workspace="$1"
  if [[ -f "$workspace/Makefile" ]] && grep -q "^test:" "$workspace/Makefile"; then
    echo "make test"
  elif [[ -f "$workspace/package.json" ]] && command -v jq >/dev/null 2>&1 \
       && jq -e '.scripts.test' "$workspace/package.json" >/dev/null 2>&1; then
    echo "npm test"
  elif [[ -f "$workspace/pyproject.toml" ]] || [[ -f "$workspace/setup.py" ]]; then
    echo "python -m pytest"
  elif [[ -f "$workspace/Cargo.toml" ]]; then
    echo "cargo test"
  elif [[ -f "$workspace/go.mod" ]]; then
    echo "go test ./..."
  else
    echo ""
  fi
}

# --- Git helpers ---------------------------------------------------------
ensure_branch() {
  local branch="$1"
  ( cd "$WORKSPACE" || exit 1
    if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      echo "ERROR: workspace is not a git repo: $WORKSPACE" >&2
      exit 1
    fi
    if git show-ref --verify --quiet "refs/heads/$branch"; then
      git checkout "$branch" >/dev/null
    else
      git checkout -b "$branch" >/dev/null
    fi
  )
}

current_commit() {
  ( cd "$WORKSPACE" && git rev-parse --short HEAD 2>/dev/null || echo "" )
}

# --- Planner integration -------------------------------------------------
# Args: <slug> <description>
# Echoes path to the generated PRD (or empty string if planner unavailable).
run_planner() {
  local slug="$1"
  local description="$2"
  local crewai_dir="$WORKSPACE/.crewai"
  local prd_dir="$WORKSPACE/.claude/context/engineering-loop/$slug"
  local prd_path="$prd_dir/PRD.md"

  if [[ ! -d "$crewai_dir" ]]; then
    log "planner: .crewai not found at $crewai_dir — skipping planner"
    echo ""
    return 0
  fi
  if ! command -v uv >/dev/null 2>&1; then
    log "planner: uv not installed — skipping planner"
    echo ""
    return 0
  fi

  local py_package="engineering_crew"
  if [[ -f "$crewai_dir/.package-name" ]]; then
    py_package="$(head -n 1 "$crewai_dir/.package-name" | tr -d '[:space:]')"
  fi

  mkdir -p "$prd_dir"

  log "planner: generating PRD for '$slug'"
  if ( cd "$crewai_dir" && \
       ENGINEERING_PLAN_OUTPUT="$prd_path" \
       uv run python -m "${py_package}.main" --task "$description" \
       >>"$LOG_FILE" 2>&1 ); then
    if [[ -s "$prd_path" ]]; then
      log "planner: wrote $prd_path"
      echo "$prd_path"
      return 0
    fi
  fi

  log "planner: PRD generation failed for '$slug' — proceeding without PRD"
  echo ""
}

# --- Build prompt for one task ------------------------------------------
build_prompt() {
  local description="$1"
  local branch="$2"
  local prd_path="$3"
  local test_command="$4"
  local previous_failure="$5"

  local prd_block="(no planner PRD)"
  if [[ -n "$prd_path" && -f "$prd_path" ]]; then
    prd_block="Reviewed implementation plan (from CrewAI engineering planner):
$(cat "$prd_path")"
  fi

  local test_block="Auto-detected test command: $test_command"
  if [[ -z "$test_command" ]]; then
    test_block="No test command was auto-detected. Decide on a project-appropriate verification step and document it in the commit message."
  fi

  local retry_block=""
  if [[ -n "$previous_failure" ]]; then
    retry_block="

Previous attempt failed verification. Read the prior output below and fix the issue before re-running tests:

---PRIOR TEST OUTPUT---
$previous_failure
---END---
"
  fi

  cat <<EOF
You are an autonomous software engineer. Your task:

---
$description
---

$prd_block

Execute this task fully:
1. Think carefully about the approach before touching any code.
2. Plan the implementation (list files to change, approach, test strategy).
3. Implement the changes.
4. Run tests: $test_block
5. If tests fail, fix the code and run tests again — repeat until passing.
6. When all tests pass, commit with a clear message (no Co-authored-by lines).

Git rules:
- You are already on branch: $branch
- Commit message format: <type>(<scope>): <description>
- No "Co-authored-by" lines in commits
- No pull requests — just commit to the branch
$retry_block
When done and tests pass, output exactly: <promise>COMPLETE</promise>
If you cannot complete the task after multiple fix attempts, output: <promise>FAILED: reason</promise>
EOF
}

# --- Run a single claude -p session -------------------------------------
# Args: <prompt>
# Outputs the session stdout to a file; returns the file path on stdout.
run_claude_session() {
  local prompt="$1"
  local stdout_file
  stdout_file="$(mktemp)"

  local cmd=(claude --permission-mode "$PERMISSION_MODE" -p "$prompt")
  if [[ -n "$MODEL" ]]; then
    cmd+=(--model "$MODEL")
  fi

  ( cd "$WORKSPACE" && "${cmd[@]}" ) > "$stdout_file" 2>>"$LOG_FILE" || true
  echo "$stdout_file"
}

# --- Run the post-session test command ----------------------------------
# Args: <test_command> -> captures output to file, echoes path; sets RC global
RUN_TESTS_RC=0
run_tests_capture() {
  local test_command="$1"
  local out_file
  out_file="$(mktemp)"
  RUN_TESTS_RC=0
  ( cd "$WORKSPACE" && bash -lc "$test_command" ) > "$out_file" 2>&1 || RUN_TESTS_RC=$?
  echo "$out_file"
}

# --- Execute a single task ----------------------------------------------
# Args: <slug> <branch> <description>
# Returns 0 if task done, 1 if failed.
execute_task() {
  local slug="$1"
  local branch="$2"
  local description="$3"

  log "task '$slug': starting on branch '$branch'"
  ensure_branch "$branch"

  local prd_path=""
  if [[ "$USE_PLANNER" -eq 1 ]]; then
    prd_path="$(run_planner "$slug" "$description")"
  fi

  local test_command
  test_command="$(detect_test_command "$WORKSPACE")"
  if [[ -n "$test_command" ]]; then
    log "task '$slug': detected test command: $test_command"
  else
    log "task '$slug': no test command detected"
  fi

  local attempt=0
  local previous_failure=""
  while (( attempt <= MAX_RETRIES )); do
    if (( attempt == 0 )); then
      log "task '$slug': claude -p attempt 1/$((MAX_RETRIES + 1))"
    else
      log "task '$slug': claude -p retry $attempt/$MAX_RETRIES"
    fi

    local prompt
    prompt="$(build_prompt "$description" "$branch" "$prd_path" "$test_command" "$previous_failure")"

    local session_out
    session_out="$(run_claude_session "$prompt")"
    local session_text
    session_text="$(cat "$session_out")"
    rm -f "$session_out"

    if echo "$session_text" | grep -qiE '<promise>FAILED'; then
      log "task '$slug': agent reported FAILED"
      return 1
    fi

    if [[ -z "$test_command" ]]; then
      # No post-session check available — trust the agent.
      if echo "$session_text" | grep -qiE '<promise>COMPLETE</promise>'; then
        log "task '$slug': agent reported COMPLETE (no post-test verification)"
        return 0
      fi
      log "task '$slug': no completion promise detected, treating attempt as failure"
      previous_failure="(no post-session test command; agent did not output <promise>COMPLETE</promise>)"
    else
      local test_out
      test_out="$(run_tests_capture "$test_command")"
      local rc="$RUN_TESTS_RC"
      if (( rc == 0 )); then
        log "task '$slug': tests passed ($test_command)"
        rm -f "$test_out"
        return 0
      fi
      log "task '$slug': tests failed (exit $rc) — capturing output for next attempt"
      previous_failure="$(tail -c 8000 "$test_out")"
      rm -f "$test_out"
    fi

    attempt=$((attempt + 1))
  done

  log "task '$slug': exhausted retries ($MAX_RETRIES) — marking failed"
  return 1
}

# --- Main ----------------------------------------------------------------
log "starting run"
log "  workspace=$WORKSPACE"
log "  tasks=$TASKS_FILE"
log "  use_planner=$USE_PLANNER max_retries=$MAX_RETRIES dry_run=$DRY_RUN"

PENDING_RECORDS=()
ALL_COUNT=0
while IFS= read -r record; do
  [[ -z "$record" ]] && continue
  ALL_COUNT=$((ALL_COUNT + 1))
  status="$(printf '%s' "$record" | cut -f2)"
  if [[ "$status" == "pending" ]]; then
    PENDING_RECORDS+=("$record")
  fi
done < <(parse_tasks)

log "parsed $ALL_COUNT task(s); ${#PENDING_RECORDS[@]} pending"

if (( DRY_RUN == 1 )); then
  echo ""
  echo "Dry-run plan:"
  if (( ${#PENDING_RECORDS[@]} == 0 )); then
    echo "  (no pending tasks)"
  fi
  for record in "${PENDING_RECORDS[@]}"; do
    slug="$(printf '%s' "$record" | cut -f1)"
    branch="$(printf '%s' "$record" | cut -f3)"
    desc_b64="$(printf '%s' "$record" | cut -f4)"
    desc="$(printf '%s' "$desc_b64" | base64 -d)"
    echo "  - slug=$slug branch=$branch"
    echo "    description: $(printf '%s' "$desc" | head -c 200)$([[ ${#desc} -gt 200 ]] && echo '…')"
  done
  exit 0
fi

SUCCESS_SLUGS=()
FAILED_SLUGS=()

for record in "${PENDING_RECORDS[@]}"; do
  slug="$(printf '%s' "$record" | cut -f1)"
  branch="$(printf '%s' "$record" | cut -f3)"
  desc_b64="$(printf '%s' "$record" | cut -f4)"
  description="$(printf '%s' "$desc_b64" | base64 -d)"

  update_task_status "$slug" "in-progress"

  if execute_task "$slug" "$branch" "$description"; then
    update_task_status "$slug" "done"
    commit_hash="$(current_commit)"
    log "task '$slug': DONE (commit=$commit_hash)"
    SUCCESS_SLUGS+=("$slug")
  else
    update_task_status "$slug" "failed"
    log "task '$slug': FAILED"
    FAILED_SLUGS+=("$slug")
  fi
done

echo ""
echo "==== Engineering Loop Summary ===="
echo "Done:   ${#SUCCESS_SLUGS[@]} (${SUCCESS_SLUGS[*]:-none})"
echo "Failed: ${#FAILED_SLUGS[@]} (${FAILED_SLUGS[*]:-none})"
echo "Log:    $LOG_FILE"

if (( ${#FAILED_SLUGS[@]} > 0 )); then
  exit 1
fi
exit 0
