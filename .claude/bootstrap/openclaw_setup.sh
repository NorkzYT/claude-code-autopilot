#!/usr/bin/env bash
set -euo pipefail

log()  { printf "\n==> %s\n" "$*"; }
warn() { printf "\n[WARN] %s\n" "$*" >&2; }
skip() { printf "    [SKIP] %s\n" "$*"; }
has()  { command -v "$1" >/dev/null 2>&1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${1:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
OPENCLAW_WRAPPER_TARGET="${HOME}/.local/bin/openclaw"
PROJECT_ENV_EXAMPLE="$PROJECT_DIR/.env.example"
PROJECT_ENV_FILE="$PROJECT_DIR/.env"
COMPOSE_FILE="$PROJECT_DIR/docker-compose.openclaw.yml"

if ! has docker; then
  warn "Docker is required for the Docker-only OpenClaw setup."
  exit 1
fi

if docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD=(docker compose)
elif has docker-compose; then
  COMPOSE_CMD=(docker-compose)
else
  warn "Docker Compose plugin is required."
  exit 1
fi

if [[ ! -f "$COMPOSE_FILE" ]]; then
  warn "Compose file not found: $COMPOSE_FILE"
  exit 1
fi

mkdir -p "$(dirname "$OPENCLAW_WRAPPER_TARGET")"

cat > "$OPENCLAW_WRAPPER_TARGET" <<EOF_WRAPPER
#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$PROJECT_DIR"
COMPOSE_FILE="\$PROJECT_DIR/docker-compose.openclaw.yml"
ENV_FILE="\$PROJECT_DIR/.env"
SERVICE="openclaw-gateway"
VIEWER_SERVICE="openclaw-browser-viewer"

if docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_CMD=(docker-compose)
else
  echo "Docker Compose is required." >&2
  exit 1
fi

compose() {
  local args=()
  if [[ -f "\$ENV_FILE" ]]; then
    args+=(--env-file "\$ENV_FILE")
  fi
  "\${COMPOSE_CMD[@]}" -f "\$COMPOSE_FILE" "\${args[@]}" "\$@"
}

ensure_started() {
  if ! compose ps --status running --services 2>/dev/null | grep -qx "\$SERVICE"; then
    compose up -d "\$SERVICE" "\$VIEWER_SERVICE" >/dev/null
  fi
}

if [[ $# -eq 0 ]]; then
  ensure_started
  if [[ -t 0 && -t 1 ]]; then
    compose exec "\$SERVICE" openclaw
  else
    compose exec -T "\$SERVICE" openclaw
  fi
  exit \$?
fi

case "\$1" in
  up)
    shift
    compose up -d "\$SERVICE" "\$VIEWER_SERVICE" "\$@"
    exit \$?
    ;;
  down)
    shift
    compose down "\$@"
    exit \$?
    ;;
  logs)
    shift
    compose logs -f "\$SERVICE" "\$VIEWER_SERVICE" "\$@"
    exit \$?
    ;;
  shell)
    shift
    ensure_started
    compose exec "\$SERVICE" /bin/bash "\$@"
    exit \$?
    ;;
  viewer-url)
    port="$(compose port "\$VIEWER_SERVICE" 6080 2>/dev/null | sed -n 's/.*://p' | head -n1)"
    if [[ -n "\${port:-}" ]]; then
      printf 'http://127.0.0.1:%s/vnc.html\n' "\$port"
    else
      echo "Viewer is not running." >&2
      exit 1
    fi
    ;;
  compose)
    shift
    compose "\$@"
    exit \$?
    ;;
  *)
    ensure_started
    if [[ -t 0 && -t 1 ]]; then
      compose exec "\$SERVICE" openclaw "\$@"
    else
      compose exec -T "\$SERVICE" openclaw "\$@"
    fi
    exit \$?
    ;;
esac
EOF_WRAPPER
chmod +x "$OPENCLAW_WRAPPER_TARGET"
log "Installed OpenClaw wrapper: $OPENCLAW_WRAPPER_TARGET"

for rcfile in "$HOME/.bashrc" "$HOME/.zshrc"; do
  if [[ -f "$rcfile" ]] || [[ "$(basename "$rcfile")" == ".bashrc" ]]; then
    touch "$rcfile"
    if ! grep -qF 'export PATH="$HOME/.local/bin:$PATH"' "$rcfile" 2>/dev/null; then
      printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$rcfile"
      log "Added ~/.local/bin to PATH in $rcfile"
    else
      skip "~/.local/bin already on PATH in $rcfile"
    fi
  fi
done

if [[ -f "$PROJECT_ENV_FILE" ]]; then
  skip "Existing .env detected at $PROJECT_ENV_FILE"
else
  log "Using defaults from $PROJECT_ENV_EXAMPLE until you create $PROJECT_ENV_FILE"
fi

log "Starting Docker OpenClaw stack..."
compose_args=()
if [[ -f "$PROJECT_ENV_FILE" ]]; then
  compose_args+=(--env-file "$PROJECT_ENV_FILE")
fi
"${COMPOSE_CMD[@]}" -f "$COMPOSE_FILE" "${compose_args[@]}" up -d openclaw-gateway openclaw-browser-viewer

VIEWER_PORT="$("${COMPOSE_CMD[@]}" -f "$COMPOSE_FILE" "${compose_args[@]}" port openclaw-browser-viewer 6080 2>/dev/null | sed -n 's/.*://p' | head -n1 || true)"
GATEWAY_PORT="$("${COMPOSE_CMD[@]}" -f "$COMPOSE_FILE" "${compose_args[@]}" port openclaw-gateway 18789 2>/dev/null | sed -n 's/.*://p' | head -n1 || true)"

cat <<EOF_SUMMARY

======================================
  Docker OpenClaw Setup Complete
======================================

  Wrapper:
    $OPENCLAW_WRAPPER_TARGET

  Compose file:
    $COMPOSE_FILE

  Gateway:
    ${GATEWAY_PORT:-18789}

  Browser viewer:
    http://127.0.0.1:${VIEWER_PORT:-6080}/vnc.html

  Next steps:
    1. Review and copy .env.example to .env if you need custom identity, ports, or tokens.
    2. Re-open your shell so ~/.local/bin is on PATH.
    3. Authenticate Anthropic subscription if needed:
       claude setup-token
       openclaw models auth paste-token --provider anthropic
    4. Authenticate OpenAI subscription OAuth if needed:
       openclaw models auth login --provider openai-codex
    5. Use the viewer URL for manual browser login and takeover when needed.

  Docker-only notes:
    - No host OpenClaw CLI is installed.
    - State, cookies, downloads, and auth stay inside Docker volumes.
    - /opt/repos is mounted read-write into the gateway container by default.

EOF_SUMMARY
