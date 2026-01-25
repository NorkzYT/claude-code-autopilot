#!/usr/bin/env bash
# Dynamic editor wrapper for Claude Code
# Automatically finds and uses VS Code (local or Remote-SSH), falls back to terminal editors
set -euo pipefail

# 1) Prefer a real "code" on PATH (local install)
if command -v code >/dev/null 2>&1; then
  exec code --wait --reuse-window "$@"
fi

# 2) Prefer VS Code Remote-SSH "remote-cli" (per-user install under ~/.vscode-server)
# Check multiple possible locations for different VS Code server versions
for pattern in \
  "$HOME/.vscode-server/cli/servers/*/server/bin/remote-cli/code" \
  "$HOME/.vscode-server/bin/*/bin/remote-cli/code" \
  "$HOME/.vscode-server/bin/*/bin/code"; do
  REMOTE_CODE="$(ls -1 $pattern 2>/dev/null | head -n1 || true)"
  if [[ -n "${REMOTE_CODE:-}" && -x "$REMOTE_CODE" ]]; then
    exec "$REMOTE_CODE" --wait --reuse-window "$@"
  fi
done

# 3) Try cursor (VS Code fork)
if command -v cursor >/dev/null 2>&1; then
  exec cursor --wait --reuse-window "$@"
fi

# 4) Fallbacks to terminal editors (nano preferred)
if command -v nano >/dev/null 2>&1; then
  exec nano "$@"
fi

if command -v vim >/dev/null 2>&1; then
  exec vim "$@"
fi

if command -v vi >/dev/null 2>&1; then
  exec vi "$@"
fi

# Final fallback - nano is almost always available
exec nano "$@"
