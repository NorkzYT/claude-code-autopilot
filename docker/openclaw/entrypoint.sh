#!/usr/bin/env bash
set -euo pipefail

mode="${1:-gateway}"
if [[ $# -gt 0 ]]; then
  shift
fi

mkdir -p "${OPENCLAW_STATE_DIR:-/home/openclaw/.openclaw}" /opt/repos

case "$mode" in
  gateway)
    openclaw config set gateway.mode local >/dev/null 2>&1 || true
    openclaw config set gateway.port "${OPENCLAW_GATEWAY_PORT:-18789}" >/dev/null 2>&1 || true
    openclaw config set gateway.bind "${OPENCLAW_GATEWAY_BIND:-all}" >/dev/null 2>&1 || true
    openclaw gateway start
    exec openclaw gateway logs --follow
    ;;
  shell)
    exec /bin/bash "$@"
    ;;
  *)
    exec "$mode" "$@"
    ;;
esac
