#!/usr/bin/env bash
set -euo pipefail

# Configure git for commits inside container
git config --global user.name "${GIT_USER_NAME:-Ralph Bot}"
git config --global user.email "${GIT_USER_EMAIL:-ralph@localhost}"
git config --global --add safe.directory /workspace

# Execute the provided command (typically: claude --permission-mode acceptEdits -p "...")
exec "$@"
