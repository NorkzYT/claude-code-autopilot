#!/usr/bin/env bash
# commit-msg-no-coauthors (managed by add_openclaw_agent.sh)
set -euo pipefail

# Blocks AI co-author trailers to keep commits authored solely by the user.
# Usage: commit-msg <path-to-commit-message>

MSG_FILE="${1:-}"
if [[ -z "$MSG_FILE" || ! -f "$MSG_FILE" ]]; then
  exit 0
fi

if grep -Eiq '^[[:space:]]*Co-Authored-By:' "$MSG_FILE"; then
  echo "ERROR: Commit message contains Co-Authored-By trailer. Remove it and retry." >&2
  exit 1
fi

exit 0
