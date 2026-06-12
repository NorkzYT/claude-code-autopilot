# Shared helpers for the openclaw-ensure-* provisioners.
#
# Every provisioner follows the same contract: read openclaw.json (falling
# back to {} when missing/empty/invalid), apply a pure jq merge filter, and
# atomically write the result back only when something changed. This file
# centralizes that contract so each provisioner only declares its defaults
# and its jq filter.
#
# Source from a provisioner script:
#   source "<dir>/lib/config-merge.sh"   # repo layout
#   source /usr/local/lib/openclaw/config-merge.sh   # image layout
#
# Functions take a LOG_TAG-style first argument so output is attributable.

# config_merge_require_jq <tag>
# Exit 0 (skip, not fail) when jq is unavailable: provisioning is best-effort
# and must never block container boot.
config_merge_require_jq() {
  local tag="$1"
  if ! command -v jq >/dev/null 2>&1; then
    echo "[$tag] jq not found; skipping (install jq to enable)" >&2
    exit 0
  fi
}

# config_merge_read_base <config-path>
# Prints the current config JSON, or {} when the file is missing, empty, or
# invalid — so a good file is never clobbered and a fresh one can be seeded.
config_merge_read_base() {
  local config="$1"
  if [[ -s "$config" ]] && jq -e . "$config" >/dev/null 2>&1; then
    cat "$config"
  else
    printf '{}'
  fi
}

# config_merge_write_if_changed <tag> <config-path> <base-json> <updated-json>
# Atomic write, world-readable (cross-UID bind-mount access). No-op when the
# merge changed nothing, so repeat runs are byte-stable and quiet.
config_merge_write_if_changed() {
  local tag="$1" config="$2" base="$3" updated="$4"
  if [[ "$updated" == "$base" ]]; then
    echo "[$tag] settings already current in $config"
    return 0
  fi
  mkdir -p "$(dirname "$config")"
  local tmp
  tmp="$(mktemp "${config}.XXXXXX")"
  printf '%s\n' "$updated" >"$tmp"
  chmod 644 "$tmp" 2>/dev/null || true
  mv -f "$tmp" "$config"
  echo "[$tag] applied settings to $config"
}
