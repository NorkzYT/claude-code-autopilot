#!/usr/bin/env bash
# OpenClaw status dashboard
# Shows comprehensive status of all OpenClaw services

set -euo pipefail

has() { command -v "$1" >/dev/null 2>&1; }

# Colors
GREEN='\033[32m'
RED='\033[31m'
YELLOW='\033[33m'
CYAN='\033[36m'
DIM='\033[2m'
BOLD='\033[1m'
RESET='\033[0m'

ok()   { printf "${GREEN}%-12s${RESET}" "$1"; }
fail() { printf "${RED}%-12s${RESET}" "$1"; }
warn() { printf "${YELLOW}%-12s${RESET}" "$1"; }

echo ""
printf "${BOLD}${CYAN}OpenClaw Status Dashboard${RESET}\n"
printf "${DIM}════════════════════════════════════════${RESET}\n"
echo ""

# --- Check if OpenClaw is installed ---
if ! has openclaw; then
  fail "NOT INSTALLED"
  echo ""
  echo "  OpenClaw is not installed."
  echo "  Run: install.sh --with-openclaw"
  echo ""
  exit 0
fi

VERSION="$(openclaw --version 2>/dev/null || echo 'unknown')"
printf "  Version:    %s\n" "$VERSION"
echo ""

# --- Gateway Status ---
printf "${BOLD}Gateway${RESET}\n"
GATEWAY_STATUS="$(openclaw gateway status --json 2>/dev/null || echo '{}')"
if echo "$GATEWAY_STATUS" | grep -q '"running":true' 2>/dev/null; then
  ok "RUNNING"
  PORT="$(echo "$GATEWAY_STATUS" | grep -oP '"port":\s*\K[0-9]+' 2>/dev/null || echo '18789')"
  UPTIME="$(echo "$GATEWAY_STATUS" | grep -oP '"uptime":\s*"\K[^"]+' 2>/dev/null || echo 'unknown')"
  printf "  Port: %s  Uptime: %s\n" "$PORT" "$UPTIME"
else
  fail "STOPPED"
  printf "  Start with: openclaw gateway start\n"
fi
echo ""

# --- Discord Status ---
printf "${BOLD}Discord${RESET}\n"
DISCORD_STATUS="$(openclaw channels status discord --json 2>/dev/null || echo '{}')"
if echo "$DISCORD_STATUS" | grep -q '"connected":true' 2>/dev/null; then
  ok "CONNECTED"
  SERVER="$(echo "$DISCORD_STATUS" | grep -oP '"server":\s*"\K[^"]+' 2>/dev/null || echo 'unknown')"
  printf "  Server: %s\n" "$SERVER"
else
  warn "DISCONNECTED"
  printf "  Setup with: openclaw channels add discord\n"
fi
echo ""

# --- Token Usage ---
printf "${BOLD}Token Usage${RESET}\n"
USAGE="$(openclaw status --usage --json 2>/dev/null || echo '{}')"
TODAY_IN="$(echo "$USAGE" | grep -oP '"input_tokens":\s*\K[0-9]+' 2>/dev/null || echo '0')"
TODAY_OUT="$(echo "$USAGE" | grep -oP '"output_tokens":\s*\K[0-9]+' 2>/dev/null || echo '0')"
CACHE="$(echo "$USAGE" | grep -oP '"cache_read_tokens":\s*\K[0-9]+' 2>/dev/null || echo '0')"
COST="$(echo "$USAGE" | grep -oP '"estimated_cost":\s*\K[0-9.]+' 2>/dev/null || echo '0')"

printf "  Today:      in=%s  out=%s  cache=%s\n" "$TODAY_IN" "$TODAY_OUT" "$CACHE"
printf "  Est. cost:  \$%s ${DIM}(Claude Max: \$200/mo flat)${RESET}\n" "$COST"

# Cache hit rate
TOTAL_IN=$((TODAY_IN + CACHE))
if [[ "$TOTAL_IN" -gt 0 ]]; then
  CACHE_RATE=$(( (CACHE * 100) / TOTAL_IN ))
  printf "  Cache rate: %s%%\n" "$CACHE_RATE"
fi
echo ""

# --- Cron Jobs ---
printf "${BOLD}Cron Jobs${RESET}\n"
CRON_LIST="$(openclaw cron list --json 2>/dev/null || echo '[]')"
ACTIVE_COUNT="$(echo "$CRON_LIST" | grep -c '"enabled":true' 2>/dev/null || echo '0')"
TOTAL_COUNT="$(echo "$CRON_LIST" | grep -c '"name"' 2>/dev/null || echo '0')"
printf "  Active: %s / %s\n" "$ACTIVE_COUNT" "$TOTAL_COUNT"

LAST_RUN="$(openclaw cron runs --last --json 2>/dev/null || echo '{}')"
LAST_NAME="$(echo "$LAST_RUN" | grep -oP '"name":\s*"\K[^"]+' 2>/dev/null || echo 'none')"
LAST_STATUS="$(echo "$LAST_RUN" | grep -oP '"status":\s*"\K[^"]+' 2>/dev/null || echo 'none')"
if [[ "$LAST_STATUS" == "success" ]]; then
  printf "  Last run:   %s " "$LAST_NAME"
  ok "$LAST_STATUS"
  echo ""
elif [[ "$LAST_STATUS" == "none" ]]; then
  printf "  Last run:   none\n"
else
  printf "  Last run:   %s " "$LAST_NAME"
  fail "$LAST_STATUS"
  echo ""
fi
echo ""

# --- Heartbeat ---
printf "${BOLD}Heartbeat${RESET}\n"
HB_ENABLED="$(echo "$CRON_LIST" | grep -A1 '"heartbeat"' | grep -oP '"enabled":\s*\K(true|false)' 2>/dev/null || echo 'false')"
if [[ "$HB_ENABLED" == "true" ]]; then
  ok "ENABLED"
  printf "  Schedule: every 30min (8AM-midnight UTC)\n"
else
  warn "DISABLED"
  printf "  Enable with: /tools:openclaw-cron heartbeat on\n"
fi
echo ""

# --- Memory/RAG ---
printf "${BOLD}Memory${RESET}\n"
MEMORY_STATUS="$(openclaw memory status --json 2>/dev/null || echo '{}')"
DOC_COUNT="$(echo "$MEMORY_STATUS" | grep -oP '"document_count":\s*\K[0-9]+' 2>/dev/null || echo '0')"
INDEX_SIZE="$(echo "$MEMORY_STATUS" | grep -oP '"index_size":\s*"\K[^"]+' 2>/dev/null || echo 'unknown')"
printf "  Documents:  %s\n" "$DOC_COUNT"
printf "  Index size: %s\n" "$INDEX_SIZE"
echo ""

printf "${DIM}════════════════════════════════════════${RESET}\n"
printf "${DIM}Claude Max: \$200/month flat rate — unlimited usage${RESET}\n"
echo ""
