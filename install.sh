#!/usr/bin/env bash
set -euo pipefail

# Re-exec with bash if run under sh/dash
if [ -z "${BASH_VERSION:-}" ]; then
  if command -v bash >/dev/null 2>&1; then
    exec bash "$0" "$@"
  fi
  echo "ERROR: bash is required (not sh)." >&2
  exit 1
fi

usage() {
  cat <<'EOF'
Install .claude/ into the current repo (or --dest) without git clone.

Usage:
  curl -fsSL https://raw.githubusercontent.com/<owner>/<repo>/<ref>/install.sh | bash -s -- [options]

Options:
  --repo <owner/repo>     Source repo (required)
  --ref <branch|tag|sha>  Git ref (default: main)
  --dest <path>           Destination directory (default: current directory)
  --force                 Overwrite existing .claude/ (preserves .claude/logs/)
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
need find
need rm
need cp

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
  echo "ERROR: --repo is required. Example: --repo NorkzYT/claude-code-autopilot" >&2
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

CLAUDE_SRC="$(find "$extract_dir" -type d -name ".claude" -maxdepth 6 | head -n 1 || true)"
if [[ -z "$CLAUDE_SRC" ]]; then
  echo "ERROR: .claude/ not found in ${REPO}@${REF}" >&2
  echo "Confirm the source repo actually contains a top-level .claude directory." >&2
  exit 1
fi

DEST_ABS="$(cd "$DEST" && pwd)"
DEST_CLAUDE="${DEST_ABS}/.claude"
DEST_LOGS="${DEST_CLAUDE}/logs"

# If .claude exists and not forcing, bail
if [[ -e "$DEST_CLAUDE" && "$FORCE" != "1" ]]; then
  echo "ERROR: Destination already has .claude/: $DEST_CLAUDE" >&2
  echo "Re-run with --force to overwrite (logs preserved)." >&2
  exit 1
fi

# Ensure destination exists
mkdir -p "$DEST_CLAUDE"

if [[ -e "$DEST_CLAUDE" && "$FORCE" == "1" ]]; then
  echo "Force install: replacing .claude contents (preserving logs/)..."

  # Make sure logs exists before we delete siblings
  mkdir -p "$DEST_LOGS"

  # Delete everything inside .claude EXCEPT logs
  # NOTE: -mindepth/-maxdepth ensures only direct children are removed
  find "$DEST_CLAUDE" -mindepth 1 -maxdepth 1 \
    ! -name "logs" \
    -exec rm -rf {} +

  # Copy source .claude into destination, excluding logs
  # Use tar streaming to preserve perms and avoid nesting
  (
    cd "$CLAUDE_SRC"
    tar --exclude='./logs' -cf - .
  ) | (
    cd "$DEST_CLAUDE"
    tar -xf -
  )

else
  echo "Installing to: $DEST_CLAUDE"
  # Copy contents (not the directory itself) to avoid .claude/.claude nesting
  cp -a "$CLAUDE_SRC/." "$DEST_CLAUDE/"
  mkdir -p "$DEST_LOGS"
fi

echo "Done. Installed .claude/ into ${DEST_ABS} (logs preserved)."
