#!/usr/bin/env bash
#
# Idempotently ensure OpenClaw's request/worker timeout settings in
# openclaw.json. This is a MERGE — every other key in the file is preserved —
# so it is safe to run on every container boot and on already-configured hosts.
#
# It exists so a fresh machine reproduces the exact long-running timeout profile
# (Discord inbound worker, AI agent run, sub-agent run, and the no-progress
# watchdog) used in production, without hand-editing JSON. All values are
# env-overridable.
#
# Companions: openclaw-ensure-models seeds the claude-max-proxy provider and
# model catalog (run it first so the provider exists for the provider timeout
# below). The proxy-side "thinking" timeout (the one that is NOT in
# openclaw.json) lives in claude-max-api-proxy/src/timeouts.ts and is configured
# via CLAUDE_PROXY_* env vars on the proxy container.
#
# Usage:
#   openclaw-ensure-timeouts [path/to/openclaw.json]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for _lib in "${OPENCLAW_CONFIG_MERGE_LIB:-}" \
            "$SCRIPT_DIR/lib/config-merge.sh" \
            /usr/local/lib/openclaw/config-merge.sh; do
  if [[ -n "$_lib" && -f "$_lib" ]]; then
    # shellcheck source=lib/config-merge.sh
    source "$_lib"
    _lib_found=1
    break
  fi
done
if [[ "${_lib_found:-0}" != "1" ]]; then
  echo "[ensure-timeouts] config-merge lib not found; skipping" >&2
  exit 0
fi

TAG="ensure-timeouts"
CONFIG="${1:-${OPENCLAW_STATE_DIR:-$HOME/.openclaw}/openclaw.json}"

# Defaults match the production profile; override per machine via env.
AGENT_TIMEOUT_SECONDS="${OPENCLAW_AGENT_TIMEOUT_SECONDS:-7200}"            # agents.defaults.timeoutSeconds (2h)
SUBAGENT_RUN_TIMEOUT_SECONDS="${OPENCLAW_SUBAGENT_RUN_TIMEOUT_SECONDS:-3600}" # agents.defaults.subagents.runTimeoutSeconds (1h)
DISCORD_INBOUND_RUN_TIMEOUT_MS="${OPENCLAW_DISCORD_INBOUND_RUN_TIMEOUT_MS:-7200000}" # channels.discord.inboundWorker.runTimeoutMs (2h)
PROXY_PROVIDER_ID="${OPENCLAW_PROXY_PROVIDER_ID:-claude-max-proxy}"        # which model provider gets a request timeout
PROXY_TIMEOUT_SECONDS="${OPENCLAW_PROXY_TIMEOUT_SECONDS:-1800}"            # models.providers[<id>].timeoutSeconds (30m)

# No-progress watchdog (OpenClaw diagnostics): how long an active run may go
# WITHOUT streaming anything OpenClaw counts as progress before it warns and
# then abort-drains the session for recovery. This is NOT a request timeout —
# it is a stall detector. The built-in defaults (~6.5m warn / ~9.5m abort) are
# too tight for heavy reasoning models (opus/fable at high thinking), which can
# go minutes between visible tokens; a slow-but-healthy run gets killed
# mid-think. Raising abort to 20m gives those runs room to finish.
STUCK_SESSION_WARN_MS="${OPENCLAW_STUCK_SESSION_WARN_MS:-600000}"          # diagnostics.stuckSessionWarnMs (10m)
STUCK_SESSION_ABORT_MS="${OPENCLAW_STUCK_SESSION_ABORT_MS:-1200000}"       # diagnostics.stuckSessionAbortMs (20m)

# A warn threshold at/above abort would never fire; clamp it (only when both are
# plain integers, so a bad override still surfaces as a clear jq error below).
if [[ "$STUCK_SESSION_WARN_MS" =~ ^[0-9]+$ && "$STUCK_SESSION_ABORT_MS" =~ ^[0-9]+$ ]] \
   && (( STUCK_SESSION_WARN_MS >= STUCK_SESSION_ABORT_MS )); then
  echo "[ensure-timeouts] warn ($STUCK_SESSION_WARN_MS) >= abort ($STUCK_SESSION_ABORT_MS); clamping warn=abort" >&2
  STUCK_SESSION_WARN_MS="$STUCK_SESSION_ABORT_MS"
fi

config_merge_require_jq "$TAG"

base="$(config_merge_read_base "$CONFIG")"

# jq auto-creates intermediate objects on assignment. The provider timeout is
# only set when that provider already exists, so we never write a half-formed
# provider (missing baseUrl/api) onto a fresh machine.
updated="$(printf '%s' "$base" | jq \
  --argjson agentTimeout "$AGENT_TIMEOUT_SECONDS" \
  --argjson subagentTimeout "$SUBAGENT_RUN_TIMEOUT_SECONDS" \
  --argjson discordInbound "$DISCORD_INBOUND_RUN_TIMEOUT_MS" \
  --argjson stuckWarn "$STUCK_SESSION_WARN_MS" \
  --argjson stuckAbort "$STUCK_SESSION_ABORT_MS" \
  --arg provider "$PROXY_PROVIDER_ID" \
  --argjson providerTimeout "$PROXY_TIMEOUT_SECONDS" '
    .agents.defaults.timeoutSeconds = $agentTimeout
    | .agents.defaults.subagents.runTimeoutSeconds = $subagentTimeout
    | .channels.discord.inboundWorker.runTimeoutMs = $discordInbound
    | .diagnostics.stuckSessionWarnMs = $stuckWarn
    | .diagnostics.stuckSessionAbortMs = $stuckAbort
    | (if (.models.providers[$provider]? // null) != null
         then .models.providers[$provider].timeoutSeconds = $providerTimeout
         else . end)
  ')"

config_merge_write_if_changed "$TAG" "$CONFIG" "$base" "$updated"
