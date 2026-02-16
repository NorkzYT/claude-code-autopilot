#!/usr/bin/env bash
# Claude Code status line script.
# Shows terminal identity name, model, context usage.
# Receives JSON on stdin with model, workspace, context_window, cost info.

input=$(cat)

# Extract values (use python if jq not available)
if command -v jq &>/dev/null; then
    MODEL=$(echo "$input" | jq -r '.model.display_name // "?"')
    CONTEXT_USED=$(echo "$input" | jq -r '.context_window.used_percentage // 0')
    COST=$(echo "$input" | jq -r '.cost.total_cost_usd // 0')
else
    MODEL="?"
    CONTEXT_USED="?"
    COST="?"
fi

# Get terminal identity from env var (set by claude-named wrapper) or identity file
NAME="${CLAUDE_TERMINAL_NAME:-}"
if [ -z "$NAME" ]; then
    IDENTITY_FILE="${CLAUDE_PROJECT_DIR:-.}/.claude/terminal-identity.local.json"
    if [ -f "$IDENTITY_FILE" ] && command -v jq &>/dev/null; then
        NAME=$(jq -r '.name // empty' "$IDENTITY_FILE" 2>/dev/null)
    fi
fi
NAME="${NAME:-unnamed}"

# ANSI colors
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
DIM='\033[2m'
RESET='\033[0m'

# OpenClaw indicator
OC_STATUS=""
if command -v openclaw &>/dev/null; then
    if openclaw gateway status --quiet 2>/dev/null; then
        OC_STATUS=" ${DIM}|${RESET} ${GREEN}OC:OK${RESET}"
    else
        OC_STATUS=" ${DIM}|${RESET} ${YELLOW}OC:OFF${RESET}"
    fi
fi

printf "${CYAN}%s${RESET} ${DIM}|${RESET} %s ${DIM}|${RESET} ctx: %.0f%% ${DIM}|${RESET} \$%.4f%b\n" \
    "$NAME" "$MODEL" "$CONTEXT_USED" "$COST" "$OC_STATUS"
