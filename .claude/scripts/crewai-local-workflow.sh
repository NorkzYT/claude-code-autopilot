#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Run the engineering planner crew for the generated .crewai project.

Usage:
  bash .claude/scripts/crewai-local-workflow.sh [options]

Options:
  --repo <path>          Workspace root that contains .crewai (default: current directory)
  --task <text>          Engineering task description to plan (required unless --dry-run)
  --context-files <csv>  Comma-separated file paths to include as crew context
  --with-proxy           Ensure local CLIProxyAPI container is started before run
  --dry-run              Skip the LLM call and print the assembled inputs
  -h, --help             Show this help
EOF
}

REPO_DIR="$(pwd)"
TASK=""
CONTEXT_FILES=""
DRY_RUN="0"
WITH_PROXY="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_DIR="${2:-}"; shift 2;;
    --task) TASK="${2:-}"; shift 2;;
    --context-files) CONTEXT_FILES="${2:-}"; shift 2;;
    --with-proxy) WITH_PROXY="1"; shift 1;;
    --dry-run) DRY_RUN="1"; shift 1;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2;;
  esac
done

if [[ ! -d "$REPO_DIR" ]]; then
  echo "ERROR: repo path does not exist: $REPO_DIR" >&2
  exit 1
fi

REPO_DIR="$(cd "$REPO_DIR" && pwd)"
CREWAI_DIR="$REPO_DIR/.crewai"
if [[ ! -d "$CREWAI_DIR" ]]; then
  echo "ERROR: .crewai not found under $REPO_DIR" >&2
  echo "Run installer with --with-crewai first." >&2
  exit 1
fi

if [[ -z "$TASK" && "$DRY_RUN" != "1" ]]; then
  echo "ERROR: --task is required (or pass --dry-run)." >&2
  usage
  exit 2
fi

if ! command -v uv >/dev/null 2>&1; then
  echo "ERROR: uv is required to run CrewAI workflows." >&2
  exit 1
fi

if [[ ! -d "$CREWAI_DIR/.venv" ]]; then
  echo "Creating .crewai virtual environment via uv sync..."
  (cd "$CREWAI_DIR" && uv sync)
fi

if [[ "$WITH_PROXY" == "1" ]]; then
  PROXY_SCRIPT="$REPO_DIR/.claude/scripts/crewai-cliproxyapi.sh"
  if [[ ! -x "$PROXY_SCRIPT" ]]; then
    echo "ERROR: proxy helper not found or not executable: $PROXY_SCRIPT" >&2
    exit 1
  fi
  bash "$PROXY_SCRIPT" up --repo "$REPO_DIR"
fi

PY_PACKAGE="engineering_crew"
if [[ -f "$CREWAI_DIR/.package-name" ]]; then
  PY_PACKAGE="$(head -n 1 "$CREWAI_DIR/.package-name" | tr -d '[:space:]')"
fi

cd "$CREWAI_DIR"

cmd=(uv run python -m "${PY_PACKAGE}.main")
if [[ "$DRY_RUN" == "1" ]]; then
  cmd+=(--dry-run)
fi
if [[ -n "$TASK" ]]; then
  cmd+=(--task "$TASK")
elif [[ "$DRY_RUN" == "1" ]]; then
  cmd+=(--task "dry-run probe")
fi
if [[ -n "$CONTEXT_FILES" ]]; then
  cmd+=(--context-files "$CONTEXT_FILES")
fi

echo "Running: ${cmd[*]}"
exec "${cmd[@]}"
