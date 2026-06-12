#!/usr/bin/env bash
#
# Idempotently ensure OpenClaw's request/worker timeout settings in
# openclaw.json. This is a MERGE — every other key in the file is preserved —
# so it is safe to run on every container boot and on already-configured hosts.
#
# It exists so a fresh machine reproduces the exact long-running timeout profile
# (Discord inbound worker, AI agent run, and sub-agent run all sit at 1h+) used
# in production, without hand-editing JSON. All values are env-overridable.
#
# Companion: the proxy-side "thinking" timeout (the one that is NOT in
# openclaw.json) lives in claude-max-api-proxy/src/timeouts.ts and is configured
# via CLAUDE_PROXY_* env vars on the proxy container.
#
# Usage:
#   openclaw-ensure-timeouts [path/to/openclaw.json]
#
set -euo pipefail

CONFIG="${1:-${OPENCLAW_STATE_DIR:-$HOME/.openclaw}/openclaw.json}"

# Defaults match the production profile; override per machine via env.
AGENT_TIMEOUT_SECONDS="${OPENCLAW_AGENT_TIMEOUT_SECONDS:-7200}"            # agents.defaults.timeoutSeconds (2h)
SUBAGENT_RUN_TIMEOUT_SECONDS="${OPENCLAW_SUBAGENT_RUN_TIMEOUT_SECONDS:-3600}" # agents.defaults.subagents.runTimeoutSeconds (1h)
DISCORD_INBOUND_RUN_TIMEOUT_MS="${OPENCLAW_DISCORD_INBOUND_RUN_TIMEOUT_MS:-7200000}" # channels.discord.inboundWorker.runTimeoutMs (2h)
PROXY_PROVIDER_ID="${OPENCLAW_PROXY_PROVIDER_ID:-claude-max-proxy}"        # which model provider gets a request timeout
PROXY_TIMEOUT_SECONDS="${OPENCLAW_PROXY_TIMEOUT_SECONDS:-1800}"            # models.providers[<id>].timeoutSeconds (30m)

if ! command -v jq >/dev/null 2>&1; then
  echo "[ensure-timeouts] jq not found; skipping (install jq to enable)" >&2
  exit 0
fi

# Read existing config, falling back to {} when missing/empty/invalid so we
# never clobber a good file but can still seed a brand-new one.
if [[ -s "$CONFIG" ]] && jq -e . "$CONFIG" >/dev/null 2>&1; then
  base="$(cat "$CONFIG")"
else
  base='{}'
fi

# jq auto-creates intermediate objects on assignment. The provider timeout is
# only set when that provider already exists, so we never write a half-formed
# provider (missing baseUrl/api) onto a fresh machine.
updated="$(printf '%s' "$base" | jq \
  --argjson agentTimeout "$AGENT_TIMEOUT_SECONDS" \
  --argjson subagentTimeout "$SUBAGENT_RUN_TIMEOUT_SECONDS" \
  --argjson discordInbound "$DISCORD_INBOUND_RUN_TIMEOUT_MS" \
  --arg provider "$PROXY_PROVIDER_ID" \
  --argjson providerTimeout "$PROXY_TIMEOUT_SECONDS" '
    .agents.defaults.timeoutSeconds = $agentTimeout
    | .agents.defaults.subagents.runTimeoutSeconds = $subagentTimeout
    | .channels.discord.inboundWorker.runTimeoutMs = $discordInbound
    | (if (.models.providers[$provider]? // null) != null
         then .models.providers[$provider].timeoutSeconds = $providerTimeout
         else . end)
  ')"

if [[ "$updated" == "$base" ]]; then
  echo "[ensure-timeouts] timeout settings already current in $CONFIG"
  exit 0
fi

# Atomic write; keep the file world-readable for cross-UID bind-mount access.
mkdir -p "$(dirname "$CONFIG")"
tmp="$(mktemp "${CONFIG}.XXXXXX")"
printf '%s\n' "$updated" >"$tmp"
chmod 644 "$tmp" 2>/dev/null || true
mv -f "$tmp" "$CONFIG"
echo "[ensure-timeouts] applied timeout settings to $CONFIG"
