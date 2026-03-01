#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "run" ]]; then
  if [[ $# -gt 1 ]]; then
    repo_path="$2"
    shift 2
  else
    repo_path="${CREWAI_REPO:-}"
    shift 1
  fi

  if [[ -z "${repo_path:-}" ]]; then
    echo "ERROR: missing repo path. Usage: run <repo-path> [crew-args...]" >&2
    exit 2
  fi

  project_dir="${repo_path%/}/.crewai"
  if [[ ! -d "$project_dir" ]]; then
    echo "ERROR: .crewai not found under $repo_path" >&2
    exit 1
  fi

  cd "$project_dir"
  if [[ ! -d .venv ]]; then
    uv sync
  fi

  if [[ -f .package-name ]]; then
    pkg="$(head -n 1 .package-name | tr -d '[:space:]')"
  else
    pkg="growth_marketing_team"
  fi

  exec uv run python -m "${pkg}.main" "$@"
fi

exec "$@"
