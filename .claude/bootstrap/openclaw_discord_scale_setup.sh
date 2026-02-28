#!/usr/bin/env bash
set -euo pipefail

# openclaw_discord_scale_setup.sh
# Interactive wizard to scale Discord usage with channel->agent lanes and
# thread-first concurrency.

log()  { printf "\n==> %s\n" "$*"; }
warn() { printf "\n[WARN] %s\n" "$*" >&2; }
has()  { command -v "$1" >/dev/null 2>&1; }

cfg_path() {
  local state_home
  state_home="${OPENCLAW_STATE_DIR:-${OPENCLAW_HOME:-$HOME/.openclaw}}"
  printf "%s/openclaw.json" "$state_home"
}

list_agents() {
  if ! has openclaw; then
    return 1
  fi
  local raw
  raw="$(openclaw agents list --json 2>/dev/null || true)"
  [[ -z "$raw" ]] && return 0

  python3 -c '
import json, sys

raw = sys.stdin.read().strip()
if not raw:
    sys.exit(0)
try:
    data = json.loads(raw)
except Exception:
    sys.exit(0)

agents = data if isinstance(data, list) else (data.get("agents") if isinstance(data, dict) else [])
if not isinstance(agents, list):
    agents = []

for a in agents:
    if not isinstance(a, dict):
        continue
    n = a.get("id") or a.get("name") or ""
    w = a.get("workspace") or ""
    if n:
        print(f"{n}\t{w}")
' <<<"$raw"
}

agent_exists() {
  local agent_id="$1"
  [[ -z "$agent_id" ]] && return 1
  list_agents | awk -F'\t' '{print $1}' | grep -qx "$agent_id"
}

agent_workspace() {
  local agent_id="$1"
  list_agents | awk -F'\t' -v id="$agent_id" '$1==id {print $2; exit}'
}

upsert_discord_scale_config() {
  local config_file="$1"
  local guild_id="$2"
  local user_id="$3"
  local require_mention="$4"
  local max_concurrent="$5"
  local lanes_json="$6"

  python3 - "$config_file" "$guild_id" "$user_id" "$require_mention" "$max_concurrent" "$lanes_json" <<'PY'
import json, os, sys
from datetime import datetime, timezone

cfg_path, guild_id, user_id, require_mention, max_concurrent, lanes_json = sys.argv[1:]

if os.path.exists(cfg_path):
    with open(cfg_path, "r", encoding="utf-8") as f:
        data = json.load(f)
else:
    data = {}

meta = data.setdefault("meta", {})
meta["lastTouchedAt"] = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")

channels = data.get("channels")
if not isinstance(channels, dict):
    channels = {}
data["channels"] = channels

discord = channels.get("discord")
if not isinstance(discord, dict):
    discord = {}
channels["discord"] = discord

discord["groupPolicy"] = "allowlist"

guilds = discord.get("guilds")
if not isinstance(guilds, dict):
    guilds = {}
discord["guilds"] = guilds

guild_cfg = guilds.get(guild_id)
if not isinstance(guild_cfg, dict):
    guild_cfg = {}
guilds[guild_id] = guild_cfg

if user_id.strip():
    users = guild_cfg.get("users")
    if not isinstance(users, list):
        users = []
    if user_id not in users:
        users.append(user_id)
    guild_cfg["users"] = users

guild_channels = guild_cfg.get("channels")
if not isinstance(guild_channels, dict):
    guild_channels = {}
guild_cfg["channels"] = guild_channels

lanes = json.loads(lanes_json)
require_mention_bool = (require_mention.lower() == "true")

for lane in lanes:
    ch = str(lane.get("channelId", "")).strip()
    if not ch:
        continue
    ch_cfg = guild_channels.get(ch)
    if not isinstance(ch_cfg, dict):
        ch_cfg = {}
    ch_cfg["allow"] = True
    ch_cfg["requireMention"] = require_mention_bool
    guild_channels[ch] = ch_cfg

bindings = data.get("bindings")
if not isinstance(bindings, list):
    bindings = []

def is_same_channel_binding(item, guild_id, channel_id):
    if not isinstance(item, dict):
        return False
    match = item.get("match")
    if not isinstance(match, dict):
        return False
    if match.get("channel") != "discord":
        return False
    peer = match.get("peer")
    if isinstance(peer, dict) and peer.get("kind") == "channel" and str(peer.get("id")) == str(channel_id):
        return True
    return match.get("guildId") == str(guild_id) and match.get("channelId") == str(channel_id)

for lane in lanes:
    ch = str(lane.get("channelId", "")).strip()
    agent = str(lane.get("agentId", "")).strip()
    if not ch:
        continue
    bindings = [b for b in bindings if not is_same_channel_binding(b, guild_id, ch)]
    if agent:
        bindings.append({
            "agentId": agent,
            "match": {
                "channel": "discord",
                "guildId": str(guild_id),
                "peer": {"kind": "channel", "id": str(ch)}
            }
        })

data["bindings"] = bindings

agents = data.get("agents")
if not isinstance(agents, dict):
    agents = {}
data["agents"] = agents
defaults = agents.get("defaults")
if not isinstance(defaults, dict):
    defaults = {}
agents["defaults"] = defaults
try:
    mc = int(max_concurrent)
    if mc > 0:
        defaults["maxConcurrent"] = mc
except Exception:
    pass

tmp = cfg_path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
os.replace(tmp, cfg_path)
PY
}

if ! has openclaw; then
  warn "OpenClaw is not installed. Run install.sh --with-openclaw first."
  exit 1
fi

echo ""
echo "=============================================="
echo "  DISCORD PARALLELISM SETUP FOR OPENCLAW"
echo "=============================================="
echo ""
echo "This wizard configures:"
echo "  - strict Discord allowlist (guild + user + channels)"
echo "  - channel -> agent lane bindings"
echo "  - concurrency cap (agents.defaults.maxConcurrent)"
echo ""
echo "Parallelism model:"
echo "  - Use one Discord thread per task to run tasks concurrently."
echo "  - Each thread gets its own session key."
echo ""

CONFIG_FILE="$(cfg_path)"
mkdir -p "$(dirname "$CONFIG_FILE")"
[[ -f "$CONFIG_FILE" ]] || echo '{}' > "$CONFIG_FILE"

echo "Known agents:"
if AGENT_ROWS="$(list_agents)"; then
  if [[ -n "$AGENT_ROWS" ]]; then
    while IFS=$'\t' read -r aid aws; do
      [[ -z "$aid" ]] && continue
      echo "  - $aid  ($aws)"
    done <<< "$AGENT_ROWS"
  else
    echo "  (none found)"
  fi
else
  echo "  (unable to query agents)"
fi
echo ""

read -rp "Discord Server ID (guild): " GUILD_ID
if [[ -z "${GUILD_ID:-}" ]]; then
  warn "Guild ID is required."
  exit 1
fi

read -rp "Your Discord User ID (strict allowlist): " USER_ID
if [[ -z "${USER_ID:-}" ]]; then
  warn "User ID is required for strict mode."
  exit 1
fi

read -rp "Require @mention for plain-text in these channels? (y/N): " REQUIRE_MENTION_ANS
REQUIRE_MENTION="false"
if [[ "$REQUIRE_MENTION_ANS" =~ ^[Yy]$ ]]; then
  REQUIRE_MENTION="true"
fi

read -rp "Max concurrent runs (agents.defaults.maxConcurrent) [8]: " MAX_CONCURRENT
MAX_CONCURRENT="${MAX_CONCURRENT:-8}"

read -rp "Primary Discord channel ID: " PRIMARY_CHANNEL
read -rp "Primary agent ID for that channel: " PRIMARY_AGENT
if [[ -z "${PRIMARY_CHANNEL:-}" || -z "${PRIMARY_AGENT:-}" ]]; then
  warn "Primary channel ID and agent ID are required."
  exit 1
fi

if ! agent_exists "$PRIMARY_AGENT"; then
  warn "Agent '$PRIMARY_AGENT' not found in current OpenClaw agents list."
  read -rp "Create it now using the same workspace as another existing agent? (y/N): " CREATE_ANS
  if [[ "$CREATE_ANS" =~ ^[Yy]$ ]]; then
    read -rp "Base agent ID to copy workspace from: " BASE_AGENT
    BASE_WS="$(agent_workspace "$BASE_AGENT" || true)"
    if [[ -z "$BASE_WS" ]]; then
      warn "Base agent '$BASE_AGENT' not found or has no workspace."
      exit 1
    fi
    if openclaw agents add "$PRIMARY_AGENT" --workspace "$BASE_WS" --non-interactive 2>/dev/null; then
      log "Created agent '$PRIMARY_AGENT' with workspace '$BASE_WS'"
    else
      warn "Failed to create agent '$PRIMARY_AGENT'."
      exit 1
    fi
  else
    exit 1
  fi
fi

LANES_JSON='[]'
LANES_JSON="$(python3 - "$PRIMARY_CHANNEL" "$PRIMARY_AGENT" <<'PY'
import json, sys
print(json.dumps([{"channelId": sys.argv[1], "agentId": sys.argv[2]}]))
PY
)"

read -rp "Add more channel->agent lanes (different channel IDs)? (y/N): " ADD_MORE
while [[ "$ADD_MORE" =~ ^[Yy]$ ]]; do
  read -rp "  Channel ID: " LANE_CHANNEL
  read -rp "  Agent ID: " LANE_AGENT
  if [[ -z "${LANE_CHANNEL:-}" || -z "${LANE_AGENT:-}" ]]; then
    warn "  Skipping empty lane."
  else
    if ! agent_exists "$LANE_AGENT"; then
      warn "  Agent '$LANE_AGENT' not found; lane skipped."
    else
      LANE_UPSERT_OUT="$(python3 - "$LANES_JSON" "$LANE_CHANNEL" "$LANE_AGENT" <<'PY'
import json, sys
lanes = json.loads(sys.argv[1])
ch = str(sys.argv[2])
ag = str(sys.argv[3])
action = "added"
for lane in lanes:
    if str(lane.get("channelId", "")).strip() == ch:
        if str(lane.get("agentId", "")).strip() == ag:
            action = "duplicate"
        else:
            lane["agentId"] = ag
            action = "replaced"
        break
else:
    lanes.append({"channelId": ch, "agentId": ag})
print(action)
print(json.dumps(lanes))
PY
)"
      LANE_ACTION="$(printf '%s\n' "$LANE_UPSERT_OUT" | head -n1)"
      LANES_JSON="$(printf '%s\n' "$LANE_UPSERT_OUT" | tail -n +2)"
      case "$LANE_ACTION" in
        duplicate) warn "  Lane already exists for channel=$LANE_CHANNEL agent=$LANE_AGENT (skipped)." ;;
        replaced)  log "Updated lane channel=$LANE_CHANNEL -> agent=$LANE_AGENT (replaced previous agent for that channel)" ;;
        *)         log "Added lane channel=$LANE_CHANNEL agent=$LANE_AGENT" ;;
      esac
    fi
  fi
  read -rp "Add another lane? (y/N): " ADD_MORE
done

upsert_discord_scale_config "$CONFIG_FILE" "$GUILD_ID" "$USER_ID" "$REQUIRE_MENTION" "$MAX_CONCURRENT" "$LANES_JSON"
log "Updated Discord scaling config at $CONFIG_FILE"

openclaw gateway start 2>/dev/null || systemctl --user restart openclaw-gateway.service 2>/dev/null || true
log "Gateway restarted to apply changes"

echo ""
echo "Configured lanes:"
python3 - "$LANES_JSON" <<'PY'
import json, sys
for lane in json.loads(sys.argv[1]):
    print(f"  - channel {lane['channelId']} -> agent {lane['agentId']}")
PY

echo ""
echo "Thread-first usage (recommended):"
echo "  1) In each lane channel, create one thread per task."
echo "  2) In each new thread, run: /new"
echo "  3) Run tasks in multiple threads concurrently."
echo "  4) Do not duplicate lanes for the same channel; threads provide parallelism."
echo ""
echo "Verify:"
echo "  openclaw config get channels.discord --json"
echo "  openclaw config get bindings --json"
echo "  openclaw status --deep"
echo ""
