#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Manage local CLIProxyAPI Docker stack used by the CrewAI scaffold.

Usage:
  bash .claude/scripts/crewai-cliproxyapi.sh <command> [options]

Commands:
  up         Start proxy container
  down       Stop proxy container
  restart    Restart proxy container
  status     Show container status
  logs       Tail proxy logs
  ui         Print local management URLs

Options:
  --repo <path>   Workspace root that contains .crewai (default: current directory)
  -h, --help      Show this help
EOF
}

REPO_DIR="$(pwd)"
CMD=""

if [[ $# -lt 1 ]]; then
  usage
  exit 2
fi

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  usage
  exit 0
fi

CMD="$1"
shift 1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_DIR="${2:-}"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2;;
  esac
done

if [[ ! -d "$REPO_DIR" ]]; then
  echo "ERROR: repo path does not exist: $REPO_DIR" >&2
  exit 1
fi

CREWAI_DIR="$(cd "$REPO_DIR" && pwd)/.crewai"
COMPOSE_FILE="$CREWAI_DIR/cliproxyapi/docker-compose.yml"

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "ERROR: proxy compose file not found: $COMPOSE_FILE" >&2
  echo "Run CrewAI setup first (installer --with-crewai)." >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: docker is required for CLIProxyAPI container mode." >&2
  exit 1
fi

compose_cmd=()
if docker compose version >/dev/null 2>&1; then
  compose_cmd=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  compose_cmd=(docker-compose)
else
  echo "ERROR: docker compose (plugin or docker-compose) is required." >&2
  exit 1
fi

run_compose() {
  "${compose_cmd[@]}" -f "$COMPOSE_FILE" "$@"
}

require_docker_daemon() {
  if ! docker info >/dev/null 2>&1; then
    echo "ERROR: docker daemon is not accessible for the current user." >&2
    echo "Try: sudo usermod -aG docker \$USER && newgrp docker" >&2
    echo "Or run with a user that can access /var/run/docker.sock." >&2
    exit 1
  fi
}

case "$CMD" in
  up)
    require_docker_daemon
    run_compose up -d
    echo "CLIProxyAPI started."
    echo "OpenAI-compatible base URL: http://127.0.0.1:8317/v1"
    echo "Management UI (if enabled): http://127.0.0.1:8085"
    ;;
  down)
    require_docker_daemon
    run_compose down
    echo "CLIProxyAPI stopped."
    ;;
  restart)
    require_docker_daemon
    run_compose down
    run_compose up -d
    echo "CLIProxyAPI restarted."
    ;;
  status)
    require_docker_daemon
    run_compose ps
    ;;
  logs)
    require_docker_daemon
    run_compose logs -f
    ;;
  ui)
    echo "OpenAI-compatible endpoint: http://127.0.0.1:8317/v1"
    echo "Management UI:             http://127.0.0.1:8085"
    echo "Proxy config file:         $CREWAI_DIR/cliproxyapi/config.yaml"
    ;;
  *)
    echo "Unknown command: $CMD" >&2
    usage
    exit 2
    ;;
esac
