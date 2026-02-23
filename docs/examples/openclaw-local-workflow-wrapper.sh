#!/usr/bin/env bash
set -euo pipefail

# Thin example launcher for the real wrapper script.
# Run this from the repo root.

exec bash ./.claude/scripts/openclaw-local-workflow.sh "$@"

