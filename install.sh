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
  --repo <owner/repo>       Source repo (required)
  --ref <branch|tag|sha>    Git ref (default: main)
  --dest <path>             Destination directory (default: current directory)
  --force                   Overwrite existing .claude/ (preserves .claude/logs/)
  --bootstrap-linux         Linux-only: run full bootstrap (devtools + extras)
                            Includes: linux_devtools.sh, install-extras.sh (wshobson agents/commands)
  --no-extras               Skip installing extras (wshobson agents/commands/skills)
EOF
}

REPO=""
REF="main"
DEST="."
FORCE="0"
BOOTSTRAP_LINUX="0"
NO_EXTRAS="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)   REPO="${2:-}"; shift 2;;
    --ref)    REF="${2:-}"; shift 2;;
    --dest)   DEST="${2:-}"; shift 2;;
    --force)  FORCE="1"; shift 1;;
    --bootstrap-linux) BOOTSTRAP_LINUX="1"; shift 1;;
    --no-extras) NO_EXTRAS="1"; shift 1;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2;;
  esac
done

need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing dependency: $1" >&2; exit 1; }; }
need tar
need find
need rm
need cp
need id
need mkdir
need chmod
need chown

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

# Find .claude directory
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
  echo "Force install: replacing .claude contents (preserving logs/, vendor/)..."

  # Ensure logs exists so it can be preserved
  mkdir -p "$DEST_LOGS"

  # Delete everything inside .claude EXCEPT logs/ and vendor/
  find "$DEST_CLAUDE" -mindepth 1 -maxdepth 1 \
    ! -name "logs" \
    ! -name "vendor" \
    -exec rm -rf {} +

  # Copy source .claude into destination, excluding logs/
  (
    cd "$CLAUDE_SRC"
    tar --exclude='./logs' --exclude='./vendor' -cf - .
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

# --- Fix permissions/ownership so Claude hooks can write logs ---
TARGET_USER="${SUDO_USER:-$(id -un)}"
TARGET_GROUP="$(id -gn "$TARGET_USER" 2>/dev/null || true)"

# If installer ran as root (common), hand ownership to the actual user.
if [[ "$(id -u)" -eq 0 ]]; then
  if [[ -n "$TARGET_GROUP" ]]; then
    echo "Setting ownership of .claude to ${TARGET_USER}:${TARGET_GROUP} ..."
    chown -R "${TARGET_USER}:${TARGET_GROUP}" "$DEST_CLAUDE" || true
  else
    echo "Setting ownership of .claude to ${TARGET_USER} ..."
    chown -R "${TARGET_USER}" "$DEST_CLAUDE" || true
  fi
fi

# Ensure logs dir exists and is writable by any user (sticky bit like /tmp)
mkdir -p "$DEST_LOGS"
chmod 1777 "$DEST_LOGS" || true
find "$DEST_LOGS" -maxdepth 1 -type f -exec chmod 666 {} \; 2>/dev/null || true

# --- Optional: Linux bootstrap (Claude Code + notify-send + LSP binaries + plugins) ---
if [[ "$BOOTSTRAP_LINUX" == "1" ]]; then
  if [[ "$(uname -s 2>/dev/null || echo '')" == "Linux" ]]; then
    # Step 1: Run linux_devtools.sh (installs git, rsync, python3, etc.)
    BOOTSTRAP_SCRIPT="$DEST_CLAUDE/bootstrap/linux_devtools.sh"
    if [[ -f "$BOOTSTRAP_SCRIPT" ]]; then
      echo "Running Linux bootstrap: $BOOTSTRAP_SCRIPT"
      chmod +x "$BOOTSTRAP_SCRIPT" 2>/dev/null || true

      # If installer ran as root, run bootstrap as the target (non-root) user
      if [[ "$(id -u)" -eq 0 ]]; then
        if command -v su >/dev/null 2>&1; then
          su - "$TARGET_USER" -c "bash \"$BOOTSTRAP_SCRIPT\""
        else
          echo "WARN: 'su' not found; running bootstrap as root."
          bash "$BOOTSTRAP_SCRIPT"
        fi
      else
        bash "$BOOTSTRAP_SCRIPT"
      fi
    else
      echo "WARN: bootstrap script not found at $BOOTSTRAP_SCRIPT"
    fi

    # Step 2: Run install-extras.sh (installs wshobson agents/commands/skills)
    if [[ "$NO_EXTRAS" != "1" ]]; then
      EXTRAS_SCRIPT="$DEST_CLAUDE/extras/install-extras.sh"
      if [[ -f "$EXTRAS_SCRIPT" ]]; then
        echo ""
        echo "Running extras installer: $EXTRAS_SCRIPT"
        chmod +x "$EXTRAS_SCRIPT" 2>/dev/null || true

        if [[ "$(id -u)" -eq 0 ]]; then
          if command -v su >/dev/null 2>&1; then
            su - "$TARGET_USER" -c "bash \"$EXTRAS_SCRIPT\" \"$DEST_ABS\""
          else
            echo "WARN: 'su' not found; running extras as root."
            bash "$EXTRAS_SCRIPT" "$DEST_ABS"
          fi
        else
          bash "$EXTRAS_SCRIPT" "$DEST_ABS"
        fi
      else
        echo "WARN: extras installer not found at $EXTRAS_SCRIPT"
      fi
    else
      echo "Skipping extras installation (--no-extras specified)."
    fi
  else
    echo "Skipping --bootstrap-linux (not Linux)."
  fi
fi

echo ""
echo "Done. Installed .claude/ into ${DEST_ABS} (logs preserved)."
echo ""
echo "Available tools:"
echo "  - .claude/extras/doctor.sh          Validate .claude/ configuration"
echo "  - .claude/extras/install-extras.sh  Install/update wshobson agents & commands"
echo ""
echo "Restart Claude Code to re-index agents/skills/commands."
