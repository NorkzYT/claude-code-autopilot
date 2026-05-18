#!/usr/bin/env bash
#
# engineering-loop.sh — Autonomous engineering driver.
#
# Reads task files from a directory or a single markdown file, then routes
# each pending task based on its **Type:** field:
#
#   coding (default) — calls claude-max-proxy HTTP API for execution, runs
#       tests, retries on failure, commits. No direct `claude` CLI.
#
#   research | creative | personal | marketing | auto | <custom> — calls the
#       CrewAI multi-crew router (Codex via CLIProxyAPI) and writes the output
#       to bin/outputs/<slug>/result.md. No test loop, no commit.
#
# Usage:
#   engineering-loop.sh [OPTIONS] <tasks-path>
#
#   <tasks-path> can be:
#     - A directory  — all *.md files in that directory are processed
#     - A single .md file — processed directly
#
# Options:
#   --workspace DIR      Repo to work in (default: cwd)
#   --use-planner        Run CrewAI planner before each coding task to generate a PRD
#   --max-retries N      Max proxy retries per coding task on test failure (default: 3)
#   --model MODEL        Claude model to request from proxy (default: claude-sonnet-4-6)
#   --proxy-url URL      claude-max-proxy base URL (default: http://localhost:3456)
#   --dry-run            Parse tasks and print what would run, no execution
#   -h, --help           Show this help
#
# Task file format (markdown):
#
#   ## Task: <slug>
#   **Status:** pending
#   **Type:** coding           # optional; coding|research|creative|auto|<custom>
#   **Branch:** feat/<slug>    # optional; only used for coding tasks
#
#   <free-form task description>
#
#   ---
#
# Status values: pending | in-progress | done | failed
# Type default: coding
#
# Environment:
#   CLAUDE_MAX_PROXY_URL  — Override proxy base URL (default: http://localhost:3456)
#

set -euo pipefail

# --- Defaults ---
WORKSPACE="$(pwd)"
USE_PLANNER=0
MAX_RETRIES=3
MODEL="${MODEL:-claude-sonnet-4-6}"
PROXY_URL="${CLAUDE_MAX_PROXY_URL:-http://localhost:3456}"
DRY_RUN=0
TASKS_PATH=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CODING_TYPES="coding|code|engineering"

usage() {
  sed -n '3,49p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# --- Parse args ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace) WORKSPACE="$2"; shift 2 ;;
    --use-planner) USE_PLANNER=1; shift ;;
    --max-retries) MAX_RETRIES="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --proxy-url) PROXY_URL="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; TASKS_PATH="${1:-}"; shift || true ;;
    -*) echo "ERROR: unknown option: $1" >&2; exit 2 ;;
    *)
      if [[ -z "$TASKS_PATH" ]]; then
        TASKS_PATH="$1"
        shift
      else
        echo "ERROR: unexpected positional arg: $1" >&2
        exit 2
      fi
      ;;
  esac
done

if [[ -z "$TASKS_PATH" ]]; then
  echo "ERROR: <tasks-path> is required (file or directory)" >&2
  usage
  exit 2
fi

# Resolve paths
WORKSPACE="$(cd "$WORKSPACE" && pwd)"
if [[ ! "$TASKS_PATH" = /* ]]; then
  TASKS_PATH="$WORKSPACE/$TASKS_PATH"
fi

if [[ ! -e "$TASKS_PATH" ]]; then
  echo "ERROR: tasks path not found: $TASKS_PATH" >&2
  exit 1
fi

# Collect task files
TASKS_FILES=()
if [[ -d "$TASKS_PATH" ]]; then
  while IFS= read -r -d '' f; do
    TASKS_FILES+=("$f")
  done < <(find "$TASKS_PATH" -maxdepth 2 -name "*.md" -not -name ".*" -print0 | sort -z)
  if (( ${#TASKS_FILES[@]} == 0 )); then
    echo "ERROR: no .md files found in directory: $TASKS_PATH" >&2
    exit 1
  fi
else
  TASKS_FILES=("$TASKS_PATH")
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

is_coding_type() {
  local t="$1"
  [[ "$t" =~ ^(coding|code|engineering|)$ ]]
}

# --- Parse tasks from a file (TSV: slug\tstatus\tbranch\ttype\tdesc_b64) ----
parse_tasks() {
  local tf="${1:-$TASKS_PATH}"
  python3 - "$tf" <<'PY'
import base64
import re
import sys
from pathlib import Path

src = Path(sys.argv[1]).read_text(encoding="utf-8")

blocks = re.split(r"(?m)^(?=## Task:\s*)", src)
for block in blocks:
    if not block.strip().startswith("## Task:"):
        continue
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
    task_type = "coding"
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
            tm = re.match(r"^\*\*Type:\*\*\s*(\S+)\s*$", stripped)
            if tm:
                task_type = tm.group(1).strip().lower()
                continue
            if stripped == "":
                in_meta = False
                continue
            in_meta = False
            desc_lines.append(line)
        else:
            desc_lines.append(line)

    description = "\n".join(desc_lines).strip()
    enc = base64.b64encode(description.encode("utf-8")).decode("ascii")
    sys.stdout.write(f"{slug}\t{status}\t{branch}\t{task_type}\t{enc}\n")
PY
}

# --- Update task status in place -----------------------------------------
# Uses CURRENT_TASKS_FILE (set per task in main loop).
update_task_status() {
  local slug="$1"
  local new_status="$2"
  python3 - "${CURRENT_TASKS_FILE:-${TASKS_FILES[0]}}" "$slug" "$new_status" <<'PY'
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
    header_m = (
        re.match(r"^##\s+Task:\s*(.+?)\s*$", block.splitlines()[0])
        if block.strip().startswith("## Task:")
        else None
    )
    if header_m and header_m.group(1).strip() == target_slug:
        new_block, n = re.subn(
            r"(?m)^(\*\*Status:\*\*\s*)\S+\s*$",
            rf"\1{new_status}",
            block,
            count=1,
        )
        if n == 0:
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

# --- Test command detection ----------------------------------------------
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
run_planner() {
  local slug="$1"
  local description="$2"
  local crewai_dir="$WORKSPACE/.crewai"
  local prd_dir="$WORKSPACE/.claude/context/engineering-loop/$slug"
  local prd_path="$prd_dir/PRD.md"

  if [[ ! -d "$crewai_dir" ]]; then
    log "planner: .crewai not found — skipping"
    echo ""; return 0
  fi
  if ! command -v uv >/dev/null 2>&1; then
    log "planner: uv not installed — skipping"
    echo ""; return 0
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
      echo "$prd_path"; return 0
    fi
  fi

  log "planner: PRD generation failed for '$slug' — proceeding without PRD"
  echo ""
}

# --- Build prompt for a coding task -------------------------------------
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
You are an autonomous software engineer.

Working directory: $WORKSPACE
Your first action must be to run: cd $WORKSPACE

Your task:
---
$description
---

$prd_block

Execute this task fully:
1. Navigate to $WORKSPACE (cd command).
2. Think carefully about the approach before touching any code.
3. Plan the implementation (list files to change, approach, test strategy).
4. Implement the changes.
5. Run tests: $test_block
6. If tests fail, fix the code and run tests again — repeat until passing.
7. When all tests pass, commit with a clear message (no Co-authored-by lines).

Git rules:
- You are already on branch: $branch
- Commit message format: <type>(<scope>): <description>
- No "Co-authored-by" lines in commits — this is mandatory
- No pull requests — just commit directly to the branch
$retry_block
When done and tests pass, output exactly: <promise>COMPLETE</promise>
If you cannot complete the task after multiple fix attempts, output: <promise>FAILED: reason</promise>
EOF
}

# --- Call claude-max-proxy -----------------------------------------------
run_claude_session() {
  local prompt="$1"
  local stdout_file
  stdout_file="$(mktemp)"

  local payload
  payload="$(python3 -c "
import json, sys
prompt = sys.stdin.read()
print(json.dumps({
    'model': sys.argv[1],
    'messages': [{'role': 'user', 'content': prompt}],
    'stream': False,
}))
" "$MODEL" <<< "$prompt")"

  log "session: POST $PROXY_URL/v1/chat/completions (model=$MODEL)"

  local response
  response="$(curl -sf --max-time 3600 \
    -X POST "$PROXY_URL/v1/chat/completions" \
    -H "Content-Type: application/json" \
    -d "$payload" 2>>"$LOG_FILE")" || {
    log "session: HTTP request to proxy failed"
    echo "" > "$stdout_file"
    echo "$stdout_file"
    return
  }

  printf '%s' "$response" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    content = data['choices'][0]['message']['content']
    sys.stdout.write(content)
except Exception as e:
    sys.stderr.write(f'[engineering-loop] proxy response parse error: {e}\n')
" > "$stdout_file" 2>>"$LOG_FILE" || true

  echo "$stdout_file"
}

# --- Test runner ---------------------------------------------------------
RUN_TESTS_RC=0
run_tests_capture() {
  local test_command="$1"
  local out_file
  out_file="$(mktemp)"
  RUN_TESTS_RC=0
  ( cd "$WORKSPACE" && bash -lc "$test_command" ) > "$out_file" 2>&1 || RUN_TESTS_RC=$?
  echo "$out_file"
}

# --- Execute a CODING task via claude-max-proxy --------------------------
execute_coding_task() {
  local slug="$1"
  local branch="$2"
  local description="$3"

  log "task '$slug' [coding]: starting on branch '$branch'"
  ensure_branch "$branch"

  local prd_path=""
  if [[ "$USE_PLANNER" -eq 1 ]]; then
    prd_path="$(run_planner "$slug" "$description")"
  fi

  local test_command
  test_command="$(detect_test_command "$WORKSPACE")"
  if [[ -n "$test_command" ]]; then
    log "task '$slug': detected test command: $test_command"
  fi

  local attempt=0
  local previous_failure=""
  while (( attempt <= MAX_RETRIES )); do
    if (( attempt == 0 )); then
      log "task '$slug': attempt 1/$((MAX_RETRIES + 1))"
    else
      log "task '$slug': retry $attempt/$MAX_RETRIES"
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
      if echo "$session_text" | grep -qiE '<promise>COMPLETE</promise>'; then
        log "task '$slug': agent reported COMPLETE (no post-test verification)"
        return 0
      fi
      log "task '$slug': no completion promise detected, treating attempt as failure"
      previous_failure="(agent did not output <promise>COMPLETE</promise>)"
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

# --- Execute a non-coding task via CrewAI --------------------------------
execute_crew_task() {
  local slug="$1"
  local task_type="$2"
  local description="$3"

  local crewai_dir="$WORKSPACE/.crewai"
  if [[ ! -d "$crewai_dir" ]]; then
    log "task '$slug' [$task_type]: .crewai not found at $crewai_dir — cannot dispatch to crew"
    return 1
  fi
  if ! command -v uv >/dev/null 2>&1; then
    log "task '$slug' [$task_type]: uv not installed — cannot run crew"
    return 1
  fi

  local py_package="engineering_crew"
  if [[ -f "$crewai_dir/.package-name" ]]; then
    py_package="$(head -n 1 "$crewai_dir/.package-name" | tr -d '[:space:]')"
  fi

  local output_dir="$WORKSPACE/bin/outputs/$slug"
  mkdir -p "$output_dir"
  local output_file="$output_dir/result.md"

  log "task '$slug' [$task_type]: dispatching to CrewAI"

  if ( cd "$crewai_dir" && \
       CREWAI_WORKSPACE="$WORKSPACE" \
       ENGINEERING_PLAN_OUTPUT="$output_file" \
       uv run python -m "${py_package}.main" \
         --type "$task_type" \
         --task "$description" \
         >>"$LOG_FILE" 2>&1 ); then
    if [[ -s "$output_file" ]]; then
      log "task '$slug' [$task_type]: output written to $output_file"
    else
      log "task '$slug' [$task_type]: crew ran but produced no output"
    fi
    return 0
  else
    log "task '$slug' [$task_type]: crew execution failed"
    return 1
  fi
}

# --- Main ----------------------------------------------------------------
log "starting run"
log "  workspace=$WORKSPACE"
log "  tasks_path=$TASKS_PATH (${#TASKS_FILES[@]} file(s))"
log "  proxy=$PROXY_URL model=$MODEL"
log "  use_planner=$USE_PLANNER max_retries=$MAX_RETRIES dry_run=$DRY_RUN"

PENDING_RECORDS=()
ALL_COUNT=0
for tf in "${TASKS_FILES[@]}"; do
  while IFS= read -r record; do
    [[ -z "$record" ]] && continue
    ALL_COUNT=$((ALL_COUNT + 1))
    status="$(printf '%s' "$record" | cut -f2)"
    if [[ "$status" == "pending" ]]; then
      # Store as: <filepath>\t<slug>\t<status>\t<branch>\t<type>\t<desc_b64>
      PENDING_RECORDS+=("$tf"$'\t'"$record")
    fi
  done < <(parse_tasks "$tf")
done

log "parsed $ALL_COUNT task(s); ${#PENDING_RECORDS[@]} pending"

if (( DRY_RUN == 1 )); then
  echo ""
  echo "Dry-run plan (${#PENDING_RECORDS[@]} pending task(s) across ${#TASKS_FILES[@]} file(s)):"
  if (( ${#PENDING_RECORDS[@]} == 0 )); then
    echo "  (no pending tasks)"
  fi
  for record in "${PENDING_RECORDS[@]}"; do
    tf="$(printf '%s' "$record" | cut -f1)"
    slug="$(printf '%s' "$record" | cut -f2)"
    branch="$(printf '%s' "$record" | cut -f4)"
    task_type="$(printf '%s' "$record" | cut -f5)"
    desc_b64="$(printf '%s' "$record" | cut -f6)"
    desc="$(printf '%s' "$desc_b64" | base64 -d)"
    echo "  - file=$(basename "$tf") slug=$slug type=$task_type branch=$branch"
    echo "    description: $(printf '%s' "$desc" | head -c 200)$([[ ${#desc} -gt 200 ]] && echo '…')"
  done
  exit 0
fi

SUCCESS_SLUGS=()
FAILED_SLUGS=()

for record in "${PENDING_RECORDS[@]}"; do
  tf="$(printf '%s' "$record" | cut -f1)"
  slug="$(printf '%s' "$record" | cut -f2)"
  branch="$(printf '%s' "$record" | cut -f4)"
  task_type="$(printf '%s' "$record" | cut -f5)"
  desc_b64="$(printf '%s' "$record" | cut -f6)"
  description="$(printf '%s' "$desc_b64" | base64 -d)"

  CURRENT_TASKS_FILE="$tf"
  update_task_status "$slug" "in-progress"

  task_ok=0
  if is_coding_type "$task_type"; then
    execute_coding_task "$slug" "$branch" "$description" && task_ok=1 || task_ok=0
  else
    execute_crew_task "$slug" "$task_type" "$description" && task_ok=1 || task_ok=0
  fi

  if (( task_ok == 1 )); then
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
