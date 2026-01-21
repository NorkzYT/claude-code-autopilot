#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

# If someone runs: sh install.sh  (dash), re-exec with bash.
if [ -z "${BASH_VERSION:-}" ]; then
  if command -v bash >/dev/null 2>&1; then
    exec bash "$0" "$@"
  else
    echo "ERROR: bash is required (not sh). Install bash and re-run." >&2
    exit 1
  fi
fi

DEFAULT_REPO="NorkzYT/claude-autopilot-kit"   # <-- CHANGE THIS ONCE
DEFAULT_REF="main"

usage() {
  cat <<'EOF'
Install .claude/ from claude-autopilot-kit into a repo WITHOUT git clone.

USAGE
  curl -fsSL https://raw.githubusercontent.com/<owner>/claude-autopilot-kit/<ref>/install.sh | bash -s -- [options]

OPTIONS
  --repo <owner/repo>     Source repo (default: baked into script)
  --ref <branch|tag|sha>  Git ref (default: main)
  --dest <path>           Destination directory (default: current directory)
  --force                 Overwrite existing .claude/ if present
  -h, --help              Show help

EXAMPLES
  curl -fsSL https://raw.githubusercontent.com/myorg/claude-autopilot-kit/main/install.sh | bash
  curl -fsSL https://raw.githubusercontent.com/myorg/claude-autopilot-kit/main/install.sh | bash -s -- --force
  curl -fsSL https://raw.githubusercontent.com/myorg/claude-autopilot-kit/v1.2.0/install.sh | bash -s -- --dest ../some-repo
EOF
}

REPO=""
REF="${DEFAULT_REF}"
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

if [[ -z "${REPO}" ]]; then
  REPO="${DEFAULT_REPO}"
fi

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

tmpdir="$(mktemp -d)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

archive="$tmpdir/repo.tgz"
extract_dir="$tmpdir/extract"
mkdir -p "$extract_dir"

# Public-friendly tarball URL (no auth needed):
# https://github.com/<owner>/<repo>/archive/<ref>.tar.gz
TARBALL_URL="https://github.com/${REPO}/archive/${REF}.tar.gz"

echo "Downloading .claude/ from ${REPO}@${REF} ..."
if [[ "$DL" == "curl" ]]; then
  curl -fsSL "$TARBALL_URL" -o "$archive"
else
  wget -qO "$archive" "$TARBALL_URL"
fi

echo "Extracting .claude/ ..."
tar -xzf "$archive" -C "$extract_dir" --wildcards '*/.claude/*' >/dev/null 2>&1 || true

CLAUDE_SRC="$(find "$extract_dir" -type d -name ".claude" -maxdepth 4 | head -n 1 || true)"
if [[ -z "$CLAUDE_SRC" ]]; then
  echo "ERROR: .claude/ not found in ${REPO}@${REF}" >&2
  exit 1
fi

DEST_ABS="$(cd "$DEST" && pwd)"
DEST_CLAUDE="${DEST_ABS}/.claude"

if [[ -e "$DEST_CLAUDE" && "$FORCE" != "1" ]]; then
  echo "ERROR: Destination already has .claude/: $DEST_CLAUDE" >&2
  echo "Re-run with --force to overwrite." >&2
  exit 1
fi

mkdir -p "$DEST_ABS"
if [[ "$FORCE" == "1" && -e "$DEST_CLAUDE" ]]; then
  echo "Removing existing: $DEST_CLAUDE"
  rm -rf "$DEST_CLAUDE"
fi

echo "Installing to: $DEST_CLAUDE"
cp -a "$CLAUDE_SRC" "$DEST_CLAUDE"

echo "Done."
echo "Next: cp .claude/settings.local.json .claude/settings.json  (if your setup expects settings.json)"
