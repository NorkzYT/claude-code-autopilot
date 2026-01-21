#!/usr/bin/env bash
set -euo pipefail

# claude-autopilot-kit/install.sh
# Installs the .claude/ folder from this repo into a target directory WITHOUT git clone.
# Works for public repos and private repos (via gh auth or GITHUB_TOKEN).

DEFAULT_REPO="NorkzYT/claude-autopilot-kit"  # <-- CHANGE THIS in your repo
DEFAULT_REF="main"

usage() {
  cat <<'EOF'
Install .claude/ from claude-autopilot-kit into a repo without cloning.

USAGE
  curl -fsSL https://raw.githubusercontent.com/<owner>/claude-autopilot-kit/<ref>/install.sh | sh -s -- [options]

OPTIONS
  --repo <owner/repo>     Source repo (default: baked into script)
  --ref <branch|tag|sha>  Git ref (default: main)
  --dest <path>           Destination directory (default: current directory)
  --force                 Overwrite existing .claude/ if present
  --method <auto|api|raw> Download method:
                            auto: try API tarball first, fallback to raw (default)
                            api:  GitHub API tarball (best for private + single request)
                            raw:  raw.githubusercontent.com (best for public)
  -h, --help              Show help

PRIVATE REPO AUTH
  Preferred: GitHub CLI logged in (gh auth login)
  Alternate: export GITHUB_TOKEN=... (classic or fine-grained token with repo read)

EXAMPLES
  # Public repo:
  curl -fsSL https://raw.githubusercontent.com/myorg/claude-autopilot-kit/main/install.sh | sh

  # Private repo using gh auth already set up:
  curl -fsSL https://raw.githubusercontent.com/myorg/claude-autopilot-kit/main/install.sh | sh -s -- --force

  # Private repo using token:
  export GITHUB_TOKEN=...
  curl -fsSL https://raw.githubusercontent.com/myorg/claude-autopilot-kit/main/install.sh | sh -s -- --force
EOF
}

REPO=""
REF="${DEFAULT_REF}"
DEST="."
FORCE="0"
METHOD="auto"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)   REPO="${2:-}"; shift 2;;
    --ref)    REF="${2:-}"; shift 2;;
    --dest)   DEST="${2:-}"; shift 2;;
    --force)  FORCE="1"; shift 1;;
    --method) METHOD="${2:-}"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2;;
  esac
done

if [[ -z "${REPO}" ]]; then
  REPO="${DEFAULT_REPO}"
fi

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
need tar
if command -v curl >/dev/null 2>&1; then
  DL="curl"
elif command -v wget >/dev/null 2>&1; then
  DL="wget"
else
  echo "Need curl or wget installed." >&2
  exit 1
fi

tmpdir="$(mktemp -d)"
cleanup() { rm -rf "$tmpdir"; }
trap cleanup EXIT

archive="$tmpdir/repo.tgz"
extract_dir="$tmpdir/extract"
mkdir -p "$extract_dir"

token_from_gh() {
  command -v gh >/dev/null 2>&1 || return 1
  gh auth status -h github.com >/dev/null 2>&1 || return 1
  gh auth token 2>/dev/null || return 1
}

TOKEN="${GITHUB_TOKEN:-}"
if [[ -z "${TOKEN}" ]]; then
  TOKEN="$(token_from_gh || true)"
fi

download_api_tarball() {
  local api_url="https://api.github.com/repos/${REPO}/tarball/${REF}"
  echo "Downloading tarball via GitHub API: ${REPO}@${REF}"
  if [[ "${DL}" == "curl" ]]; then
    if [[ -n "${TOKEN}" ]]; then
      curl -fsSL -H "Authorization: token ${TOKEN}" -H "Accept: application/vnd.github+json" "$api_url" -o "$archive"
    else
      curl -fsSL -H "Accept: application/vnd.github+json" "$api_url" -o "$archive"
    fi
  else
    if [[ -n "${TOKEN}" ]]; then
      wget -qO "$archive" --header="Authorization: token ${TOKEN}" --header="Accept: application/vnd.github+json" "$api_url"
    else
      wget -qO "$archive" --header="Accept: application/vnd.github+json" "$api_url"
    fi
  fi
}

extract_claude_from_tarball() {
  echo "Extracting .claude/ from tarball..."
  # tarball has a top-level prefix like <owner>-<repo>-<sha>/
  tar -xzf "$archive" -C "$extract_dir" --wildcards '*/.claude/*' >/dev/null 2>&1 || true
  local src
  src="$(find "$extract_dir" -type d -name ".claude" -maxdepth 3 | head -n 1 || true)"
  if [[ -z "$src" ]]; then
    return 1
  fi
  echo "$src"
}

install_to_dest() {
  local src="$1"
  local dest_abs
  dest_abs="$(cd "$DEST" && pwd)"
  local dest_claude="${dest_abs}/.claude"

  if [[ -e "$dest_claude" && "$FORCE" != "1" ]]; then
    echo "Destination already has .claude/: $dest_claude" >&2
    echo "Re-run with --force to overwrite." >&2
    exit 1
  fi

  mkdir -p "$dest_abs"
  if [[ "$FORCE" == "1" && -e "$dest_claude" ]]; then
    echo "Removing existing: $dest_claude"
    rm -rf "$dest_claude"
  fi

  echo "Installing to: $dest_claude"
  cp -a "$src" "$dest_claude"
  echo "Done."
}

download_raw_fallback() {
  # Raw cannot read private repos without auth. We only use this for public.
  # If repo is private and TOKEN exists, API method is the correct route.
  local base="https://raw.githubusercontent.com/${REPO}/${REF}"

  echo "Raw fallback (public only): ${base}/.claude/"
  echo "Refusing raw fallback for private installs. Use gh auth or GITHUB_TOKEN." >&2
  return 1
}

do_api() {
  download_api_tarball
  local src
  src="$(extract_claude_from_tarball)" || {
    echo "No .claude/ found in ${REPO}@${REF}" >&2
    exit 1
  }
  install_to_dest "$src"
}

case "$METHOD" in
  api) do_api;;
  raw) download_raw_fallback;;
  auto)
    # API is best for both public and private. If it fails unauthenticated on private,
    # user needs gh auth or a token.
    if do_api 2>/dev/null; then
      exit 0
    fi
    echo "API download failed."
    echo "If the repo is private: run 'gh auth login' OR export GITHUB_TOKEN with read access." >&2
    exit 1
    ;;
  *) echo "Unknown --method: $METHOD" >&2; usage; exit 2;;
esac
