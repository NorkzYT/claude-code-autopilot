#!/usr/bin/env bash
set -euo pipefail

VNC_HOST="${VNC_HOST:-openclaw-gateway}"
VNC_PORT="${VNC_PORT:-5900}"
VIEWER_PORT="${VIEWER_PORT:-6080}"

exec /opt/novnc/utils/novnc_proxy --vnc "${VNC_HOST}:${VNC_PORT}" --listen "${VIEWER_PORT}"
