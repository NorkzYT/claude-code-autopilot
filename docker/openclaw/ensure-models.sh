#!/usr/bin/env bash
#
# Idempotently ensure the claude-max-proxy model provider, its model list,
# and the agent model aliases in openclaw.json. This is a MERGE — every other
# key in the file is preserved, existing provider keys and aliases win over
# defaults — so it is safe to run on every container boot and on
# already-configured hosts.
#
# It exists so a machine picks up new proxy models (e.g. claude-fable) on
# `make update` without hand-editing JSON, and so a fresh machine reproduces
# the production model profile automatically.
#
# What it ensures (defaults; all env-overridable):
#   models.mode                                  = "merge" (only when unset)
#   models.providers.claude-max-proxy            = { baseUrl, api, auth, apiKey }
#                                                  (existing keys preserved)
#   models.providers.claude-max-proxy.models[]   += claude-sonnet/claude-opus/
#                                                   claude-fable (by id; never
#                                                   removes or rewrites entries)
#   agents.defaults.models["<provider>/<id>"]    += { alias } (existing win)
#   agents.defaults.model.primary                = $OPENCLAW_MODEL_PRIMARY
#                                                  (only when unset)
#   agents.defaults.model.fallbacks              = $OPENCLAW_MODEL_FALLBACKS
#                                                  (only when set and unset in file)
#
# Companion: openclaw-ensure-timeouts owns every timeout key, including the
# provider's timeoutSeconds — run this script FIRST so the provider block
# exists for it on a fresh machine.
#
# Usage:
#   openclaw-ensure-models [path/to/openclaw.json]
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
  echo "[ensure-models] config-merge lib not found; skipping" >&2
  exit 0
fi

TAG="ensure-models"
CONFIG="${1:-${OPENCLAW_STATE_DIR:-$HOME/.openclaw}/openclaw.json}"

PROXY_PROVIDER_ID="${OPENCLAW_PROXY_PROVIDER_ID:-claude-max-proxy}"
PROXY_BASE_URL="${OPENCLAW_PROXY_BASE_URL:-http://claude-max-proxy:3456/v1}"
PROXY_API="${OPENCLAW_PROXY_API:-openai-completions}"
PROXY_API_KEY="${OPENCLAW_PROXY_API_KEY:-ignored}"
MODEL_PRIMARY="${OPENCLAW_MODEL_PRIMARY:-claude-max-proxy/claude-opus}"
MODEL_FALLBACKS="${OPENCLAW_MODEL_FALLBACKS:-}"

# The model catalog the proxy serves. Add new families here (or override via
# env) and every machine converges on the next boot/update. `alias` becomes
# the short name usable in chat (/model fable).
DEFAULT_MODELS_JSON='[
  {"id": "claude-sonnet", "name": "Claude Sonnet (latest, Max Proxy)", "alias": "sonnet"},
  {"id": "claude-opus",   "name": "Claude Opus (latest, Max Proxy)",   "alias": "opus"},
  {"id": "claude-fable",  "name": "Claude Fable (latest, Max Proxy)",  "alias": "fable"}
]'
MODELS_JSON="${OPENCLAW_PROXY_MODELS_JSON:-$DEFAULT_MODELS_JSON}"

config_merge_require_jq "$TAG"

if ! printf '%s' "$MODELS_JSON" | jq -e 'type == "array" and all(.[]; .id != null)' >/dev/null 2>&1; then
  echo "[$TAG] OPENCLAW_PROXY_MODELS_JSON is not a JSON array of {id,...}; refusing to provision" >&2
  exit 1
fi
if [[ -n "$MODEL_FALLBACKS" ]] && ! printf '%s' "$MODEL_FALLBACKS" | jq -e 'type == "array"' >/dev/null 2>&1; then
  echo "[$TAG] OPENCLAW_MODEL_FALLBACKS is not a JSON array; refusing to provision" >&2
  exit 1
fi

base="$(config_merge_read_base "$CONFIG")"

updated="$(printf '%s' "$base" | jq \
  --arg provider "$PROXY_PROVIDER_ID" \
  --arg baseUrl "$PROXY_BASE_URL" \
  --arg api "$PROXY_API" \
  --arg apiKey "$PROXY_API_KEY" \
  --arg primary "$MODEL_PRIMARY" \
  --argjson models "$MODELS_JSON" \
  --argjson fallbacks "${MODEL_FALLBACKS:-null}" '
    .models.mode = (.models.mode // "merge")
    # Provider connection block: defaults on the left, existing keys win.
    | .models.providers[$provider] = (
        {baseUrl: $baseUrl, api: $api, auth: "api-key", apiKey: $apiKey}
        + (.models.providers[$provider] // {})
      )
    # Model catalog: append entries whose id is missing; never rewrite or
    # remove what is already there (user edits to names survive).
    | .models.providers[$provider].models = (
        (.models.providers[$provider].models // []) as $existing
        | $existing + ($models
            | map(select(.id as $id | ($existing | map(.id) | index($id)) == null))
            | map({id, name}))
      )
    # Aliases: defaults on the left, existing alias entries win.
    | .agents.defaults.models = (
        ($models
          | map(select((.alias // "") != ""))
          | map({key: ($provider + "/" + .id), value: {alias: .alias}})
          | from_entries)
        + (.agents.defaults.models // {})
      )
    # Default model: seed only when the machine has not chosen one.
    | (if ((.agents.defaults.model.primary // "") == "") and ($primary != "")
         then .agents.defaults.model.primary = $primary
         else . end)
    | (if ($fallbacks != null) and ((.agents.defaults.model.fallbacks // null) == null)
         then .agents.defaults.model.fallbacks = $fallbacks
         else . end)
  ')"

config_merge_write_if_changed "$TAG" "$CONFIG" "$base" "$updated"
