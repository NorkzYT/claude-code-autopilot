#!/usr/bin/env bash
set -euo pipefail

# Re-exec with bash if run under sh/dash
if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi

usage() {
  cat <<'EOF'
Install .claude/ into the current repo (or --dest) without git clone.

Usage:
  curl -fsSL https://raw.githubusercontent.com/<owner>/<repo>/<ref>/install.sh | bash -s -- [options]

Options:
  --repo <owner/repo>     Source repo (default: inferred from script URL if possible, else required)
  --ref <branch|tag|sha>  Git ref (default: main)
  --dest <path>           Destination directory (default: current directory)
  --force                 Overwrite existing .claude/
EOF
}

REPO=""
REF="main"
DEST="."
FORCE="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)   REPO="${2:-}"; shift 2;;
    --ref)    REF="${2:-}"; shift 2;;
    --dest)   DEST="${2:-}"; shift 2;;
    --force)  FORCE="1"; shift 1;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2;;
  esac
done

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
need tar

DL=""
if command -v curl >/dev/null 2>&1; then
  DL="curl"
elif command -v wget >/dev/null 2>&1; then
  DL="wget"
else
  echo "Missing dependency: curl or wget" >&2
  exit 1
fi

if [[ -z "${REPO}" ]]; then
  echo "ERROR: --repo is required for now. Example: --repo NorkzYT/claude-code-autopilot" >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

archive="$tmpdir/repo.tgz"
extract_dir="$tmpdir/extract"
mkdir -p "$extract_dir"

TARBALL_URL="https://github.com/${REPO}/archive/${REF}.tar.gz"

echo "Downloading ${REPO}@${REF} ..."
if [[ "$DL" == "curl" ]]; then
  curl -fsSL "$TARBALL_URL" -o "$archive"
else
  wget -qO "$archive" "$TARBALL_URL"
fi

echo "Extracting .claude/ ..."
tar -xzf "$archive" -C "$extract_dir" --wildcards '*/.claude/*' >/dev/null 2>&1 || true

CLAUDE_SRC="$(find "$extract_dir" -type d -name ".claude" -maxdepth 5 | head -n 1 || true)"
if [[ -z "$CLAUDE_SRC" ]]; then
  echo "ERROR: .claude/ not found in ${REPO}@${REF}" >&2
  echo "Confirm the source repo actually contains a top-level .claude directory." >&2
  exit 1
fi

DEST_ABS="$(cd "$DEST" && pwd)"
DEST_CLAUDE="${DEST_ABS}/.claude"

if [[ -e "$DEST_CLAUDE" && "$FORCE" != "1" ]]; then
  echo "ERROR: Destination already has .claude/: $DEST_CLAUDE" >&2
  echo "Re-run with --force to overwrite." >&2
  exit 1
fi

if [[ "$FORCE" == "1" && -e "$DEST_CLAUDE" ]]; then
  echo "Removing existing: $DEST_CLAUDE"
  rm -rf "$DEST_CLAUDE"
fi

echo "Installing to: $DEST_CLAUDE"
cp -a "$CLAUDE_SRC" "$DEST_CLAUDE"

# --- Fix permissions/ownership so Claude hooks can write logs ---
TARGET_USER="${SUDO_USER:-$(id -un)}"
TARGET_GROUP="$(id -gn "$TARGET_USER" 2>/dev/null || true)"

# If we are root (common in servers/containers), ensure the install is owned by the real user.
if [[ "$(id -u)" -eq 0 ]]; then
  if [[ -n "$TARGET_GROUP" ]]; then
    echo "Setting ownership of .claude to ${TARGET_USER}:${TARGET_GROUP} ..."
    chown -R "${TARGET_USER}:${TARGET_GROUP}" "$DEST_CLAUDE" || true
  else
    echo "Setting ownership of .claude to ${TARGET_USER} ..."
    chown -R "${TARGET_USER}" "$DEST_CLAUDE" || true
  fi
fi

# Ensure logs dir exists and is writable by owner (prevents PermissionError in hooks)
mkdir -p "$DEST_LOGS"
chmod u+rwx "$DEST_LOGS" || true
# If log files already exist, make them owner-writable
find "$DEST_LOGS" -type f -maxdepth 1 -exec chmod u+rw {} \; 2>/dev/null || true


echo "Done. Installed .claude/ into ${DEST_ABS}"
