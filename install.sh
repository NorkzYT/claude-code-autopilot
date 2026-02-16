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
  --with-openclaw           Install and configure OpenClaw integration
EOF
}

REPO=""
REF="main"
DEST="."
FORCE="0"
BOOTSTRAP_LINUX="0"
NO_EXTRAS="0"
export INSTALL_OPENCLAW="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)   REPO="${2:-}"; shift 2;;
    --ref)    REF="${2:-}"; shift 2;;
    --dest)   DEST="${2:-}"; shift 2;;
    --force)  FORCE="1"; shift 1;;
    --bootstrap-linux) BOOTSTRAP_LINUX="1"; shift 1;;
    --no-extras) NO_EXTRAS="1"; shift 1;;
    --with-openclaw) INSTALL_OPENCLAW="1"; shift 1;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2;;
  esac
done

# --- Auto-install missing dependencies on Linux ---
ensure_dependencies() {
  [[ "$(uname -s 2>/dev/null)" == "Linux" ]] || return 0

  # Detect package manager
  local pm=""
  if command -v apt-get >/dev/null 2>&1; then pm="apt-get"
  elif command -v dnf >/dev/null 2>&1; then pm="dnf"
  elif command -v yum >/dev/null 2>&1; then pm="yum"
  elif command -v apk >/dev/null 2>&1; then pm="apk"
  elif command -v pacman >/dev/null 2>&1; then pm="pacman"
  elif command -v zypper >/dev/null 2>&1; then pm="zypper"
  else
    echo "WARN: No supported package manager found. Skipping auto-install." >&2
    return 0
  fi

  # Map command -> package name per distro family
  # Format: "command:apt:dnf:apk:pacman:zypper"
  local mappings=(
    "curl:curl:curl:curl:curl:curl"
    "tar:tar:tar:tar:tar:tar"
    "git:git:git:git:git:git"
    "rsync:rsync:rsync:rsync:rsync:rsync"
    "jq:jq:jq:jq:jq:jq"
    "python3:python3:python3:python3:python:python3"
    "sudo:sudo:sudo:sudo:sudo:sudo"
    "sed:sed:sed:sed:sed:sed"
    "grep:grep:grep:grep:grep:grep"
    "find:findutils:findutils:findutils:findutils:findutils"
    "hostname:hostname:hostname::inetutils:hostname"
    "cmp:diffutils:diffutils:diffutils:diffutils:diffutils"
    "tput:ncurses-bin:ncurses:ncurses:ncurses:ncurses"
    "unzip:unzip:unzip:unzip:unzip:unzip"
    "getent:libc-bin:glibc-common::glibc:glibc"
  )

  # Determine column index for this package manager
  local col
  case "$pm" in
    apt-get) col=2;;
    dnf|yum) col=3;;
    apk)     col=4;;
    pacman)  col=5;;
    zypper)  col=6;;
  esac

  # Collect missing packages
  local missing=()
  local entry cmd pkg
  for entry in "${mappings[@]}"; do
    cmd="${entry%%:*}"
    pkg="$(echo "$entry" | cut -d: -f"$col")"
    [[ -z "$pkg" ]] && continue
    command -v "$cmd" >/dev/null 2>&1 && continue
    # Avoid duplicates
    local dup=0
    local m
    for m in "${missing[@]+"${missing[@]}"}"; do
      [[ "$m" == "$pkg" ]] && { dup=1; break; }
    done
    [[ "$dup" -eq 1 ]] && continue
    missing+=("$pkg")
  done

  [[ ${#missing[@]} -eq 0 ]] && return 0

  echo "Installing missing dependencies: ${missing[*]}"

  # Build install prefix (sudo if needed and available)
  local pfx=""
  if [[ "$(id -u)" -ne 0 ]]; then
    if command -v sudo >/dev/null 2>&1; then
      pfx="sudo "
    else
      echo "WARN: Not root and sudo not available. Cannot install packages." >&2
      return 0
    fi
  fi

  case "$pm" in
    apt-get)
      ${pfx}apt-get update -qq
      ${pfx}apt-get install -y -qq "${missing[@]}"
      ;;
    dnf)
      ${pfx}dnf install -y -q "${missing[@]}"
      ;;
    yum)
      ${pfx}yum install -y -q "${missing[@]}"
      ;;
    apk)
      ${pfx}apk update --quiet
      ${pfx}apk add --quiet "${missing[@]}"
      ;;
    pacman)
      ${pfx}pacman -Sy --noconfirm --quiet "${missing[@]}"
      ;;
    zypper)
      ${pfx}zypper --quiet refresh
      ${pfx}zypper install -y --quiet "${missing[@]}"
      ;;
  esac

  echo "Dependencies installed."
}

ensure_dependencies

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

# --- Install claude-editor wrapper script (dynamic VS Code / terminal editor) ---
EDITOR_SCRIPT="$DEST_CLAUDE/scripts/claude-editor.sh"
if [[ -f "$EDITOR_SCRIPT" ]]; then
  echo "Installing claude-editor wrapper to /usr/local/bin/..."
  chmod +x "$EDITOR_SCRIPT" 2>/dev/null || true

  # Create target directory if it doesn't exist
  if [[ "$(id -u)" -eq 0 ]]; then
    mkdir -p /usr/local/bin
    cp "$EDITOR_SCRIPT" /usr/local/bin/claude-editor
    chmod +x /usr/local/bin/claude-editor
    echo "  Installed: /usr/local/bin/claude-editor"
  else
    # Not root - try with sudo
    if command -v sudo >/dev/null 2>&1; then
      sudo mkdir -p /usr/local/bin 2>/dev/null || true
      if sudo cp "$EDITOR_SCRIPT" /usr/local/bin/claude-editor 2>/dev/null; then
        sudo chmod +x /usr/local/bin/claude-editor
        echo "  Installed: /usr/local/bin/claude-editor"
      else
        echo "  WARN: Could not install to /usr/local/bin (no sudo access)"
        echo "  To install manually, run:"
        echo "    sudo cp \"$EDITOR_SCRIPT\" /usr/local/bin/claude-editor && sudo chmod +x /usr/local/bin/claude-editor"
      fi
    else
      echo "  WARN: sudo not available - skipping system-wide claude-editor install"
      echo "  To install manually, run:"
      echo "    sudo cp \"$EDITOR_SCRIPT\" /usr/local/bin/claude-editor && sudo chmod +x /usr/local/bin/claude-editor"
    fi
  fi
else
  echo "WARN: claude-editor script not found at $EDITOR_SCRIPT"
fi

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

# --- Optional: OpenClaw integration ---
if [[ "$INSTALL_OPENCLAW" == "1" ]]; then
  OPENCLAW_SCRIPT="$DEST_CLAUDE/bootstrap/openclaw_setup.sh"
  if [[ -f "$OPENCLAW_SCRIPT" ]]; then
    echo ""
    echo "Running OpenClaw setup: $OPENCLAW_SCRIPT"
    chmod +x "$OPENCLAW_SCRIPT" 2>/dev/null || true

    if [[ "$(id -u)" -eq 0 ]]; then
      if command -v su >/dev/null 2>&1; then
        su - "$TARGET_USER" -c "bash \"$OPENCLAW_SCRIPT\" \"$DEST_ABS\""
      else
        echo "WARN: 'su' not found; running OpenClaw setup as root."
        bash "$OPENCLAW_SCRIPT" "$DEST_ABS"
      fi
    else
      bash "$OPENCLAW_SCRIPT" "$DEST_ABS"
    fi
  else
    echo "WARN: OpenClaw setup script not found at $OPENCLAW_SCRIPT"
  fi
fi

echo ""
echo "Done. Installed .claude/ into ${DEST_ABS} (logs preserved)."
echo ""

# --- Setup user-level ~/.claude/CLAUDE.md for autopilot default ---
USER_HOME=""
if [[ "$(id -u)" -eq 0 && -n "${SUDO_USER:-}" ]]; then
  USER_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6 2>/dev/null || echo "")"
fi
if [[ -z "$USER_HOME" ]]; then
  USER_HOME="$HOME"
fi

USER_CLAUDE_DIR="$USER_HOME/.claude"
USER_CLAUDE_MD="$USER_CLAUDE_DIR/CLAUDE.md"

echo "Setting up user-level autopilot default..."
mkdir -p "$USER_CLAUDE_DIR"

cat > "$USER_CLAUDE_MD" << 'AUTOPILOT_EOF'
Use the autopilot subagent (Task tool with subagent_type=autopilot) for this task
AUTOPILOT_EOF

# Fix ownership if running as root
if [[ "$(id -u)" -eq 0 && -n "${SUDO_USER:-}" ]]; then
  chown -R "${TARGET_USER}:${TARGET_GROUP}" "$USER_CLAUDE_DIR" 2>/dev/null || \
  chown -R "${TARGET_USER}" "$USER_CLAUDE_DIR" 2>/dev/null || true
fi

echo "  Created: $USER_CLAUDE_MD"
echo ""

# --- Setup cca alias in shell rc files ---
CCA_ALIAS="alias cca='${DEST_ABS}/.claude/bin/claude-named --dangerously-skip-permissions'"
CCA_COMMENT="# Claude Code autopilot alias"

for rcfile in "$USER_HOME/.bashrc" "$USER_HOME/.zshrc"; do
  if [[ -f "$rcfile" ]] || [[ "$(basename "$rcfile")" == ".bashrc" ]]; then
    touch "$rcfile" 2>/dev/null || true
    if ! grep -qF "alias cca=" "$rcfile" 2>/dev/null; then
      printf '\n%s\n%s\n' "$CCA_COMMENT" "$CCA_ALIAS" >> "$rcfile"
      echo "  Added cca alias to $rcfile"
    else
      echo "  cca alias already present in $rcfile"
    fi
  fi
done

# Fix ownership of rc files if running as root
if [[ "$(id -u)" -eq 0 && -n "${SUDO_USER:-}" ]]; then
  for rcfile in "$USER_HOME/.bashrc" "$USER_HOME/.zshrc"; do
    [[ -f "$rcfile" ]] && chown "${TARGET_USER}" "$rcfile" 2>/dev/null || true
  done
fi

# Source the current shell's rc file so the alias is available immediately
# (works when install.sh is run directly; piped curl|bash inherits this subshell)
CURRENT_SHELL="$(basename "${SHELL:-bash}")"
if [[ "$CURRENT_SHELL" == "zsh" && -f "$USER_HOME/.zshrc" ]]; then
  source "$USER_HOME/.zshrc" 2>/dev/null || true
elif [[ -f "$USER_HOME/.bashrc" ]]; then
  source "$USER_HOME/.bashrc" 2>/dev/null || true
fi

echo ""

# --- Show ntfy.sh subscription info ---
HOSTNAME="$(hostname 2>/dev/null || echo 'unknown')"
# Sanitize hostname: lowercase, replace non-alphanumeric with hyphens
NTFY_TOPIC="claude-code-$(echo "$HOSTNAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g')"

echo "=============================================="
echo "  NOTIFICATIONS SETUP (ntfy.sh)"
echo "=============================================="
echo ""
echo "  Your default ntfy.sh topic: ${NTFY_TOPIC}"
echo ""
echo "  Subscribe to receive notifications when Claude needs your attention:"
echo ""
echo "  Browser:  https://ntfy.sh/${NTFY_TOPIC}"
echo "  Android:  Install ntfy app → Subscribe to '${NTFY_TOPIC}'"
echo "  iOS:      Install ntfy app → Subscribe to '${NTFY_TOPIC}'"
echo "  CLI:      ntfy subscribe ${NTFY_TOPIC}"
echo ""
echo "  Custom topic (optional):"
echo "    export CLAUDE_NTFY_TOPIC=\"your-custom-topic\""
echo "    # Or create: ~/.config/claude-code/ntfy_topic"
echo ""
echo "  Other notification backends (optional):"
echo "    export CLAUDE_DISCORD_WEBHOOK=\"https://discord.com/api/webhooks/...\""
echo "    export CLAUDE_SLACK_WEBHOOK=\"https://hooks.slack.com/services/...\""
echo "    export CLAUDE_PUSHOVER_USER=\"...\" CLAUDE_PUSHOVER_TOKEN=\"...\""
echo ""
echo "=============================================="
echo ""
echo "=============================================="
echo "  TERMINAL NAMES & cca ALIAS"
echo "=============================================="
echo ""
echo "  Each Claude session gets a random name (e.g., cosmic-penguin)"
echo "  so you can identify multiple terminals in notifications."
echo ""
echo "  Launch Claude with the cca alias:"
echo "    cca"
echo ""
echo "  This runs: claude --dangerously-skip-permissions"
echo "  with automatic terminal naming."
echo ""
echo "  If 'cca' is not found, open a new shell or run:"
echo "    source ~/.bashrc   # or source ~/.zshrc"
echo ""
echo "Available tools:"
echo "  - cca                               Launch Claude with terminal naming + skip-permissions"
echo "  - .claude/extras/doctor.sh          Validate .claude/ configuration"
echo "  - .claude/extras/install-extras.sh  Install/update wshobson agents & commands"
echo ""
echo "=============================================="
echo "  EXTERNAL EDITOR (Ctrl+G)"
echo "=============================================="
echo ""
echo "  Installed: claude-editor (dynamic VS Code wrapper)"
echo ""
echo "  Press Ctrl+G in Claude Code to open an external editor."
echo "  The wrapper automatically detects and uses:"
echo "    1. VS Code (local install)"
echo "    2. VS Code Remote-SSH (per-user ~/.vscode-server)"
echo "    3. Cursor (VS Code fork)"
echo "    4. Falls back to nano/vim if no GUI editor found"
echo ""
echo "  VS Code keybinding conflict fix (if Ctrl+G opens directory picker):"
echo "    Add to your VS Code keybindings.json:"
echo '    {"key": "ctrl+g", "command": "-workbench.action.terminal.goToRecentDirectory", "when": "terminalFocus"},'
echo '    {"key": "ctrl+shift+alt+p", "command": "workbench.action.terminal.goToRecentDirectory", "when": "terminalFocus"}'
echo "    (Or use \"key\": \"escape\" to disable completely)"
echo ""
echo "=============================================="
echo ""
echo "=============================================="
echo "  PRODUCTIVITY TIP: Plan Mode Context Rotation"
echo "=============================================="
echo ""
echo "  Instead of /clear when context gets large:"
echo "    1. At ~50% context, switch to PLAN mode and send your prompt"
echo "    2. Claude drafts a plan using all accumulated context"
echo "    3. Select \"Yes, clear context and bypass permissions\""
echo ""
echo "  The plan preserves your session knowledge across the reset."
echo ""
echo "=============================================="
echo ""
if [[ "$INSTALL_OPENCLAW" == "1" ]]; then
  echo "=============================================="
  echo "  OPENCLAW INTEGRATION"
  echo "=============================================="
  echo ""
  echo "  OpenClaw has been configured for this workspace."
  echo ""
  echo "  Start the gateway:"
  echo "    openclaw gateway start"
  echo ""
  echo "  Auth with Claude Max:"
  echo "    claude setup-token"
  echo "    openclaw models auth paste-token --provider anthropic"
  echo ""
  echo "  Setup Discord:"
  echo "    openclaw channels add discord"
  echo ""
  echo "  Status:"
  echo "    openclaw status"
  echo ""
  echo "=============================================="
  echo ""
fi
echo "Restart Claude Code to re-index agents/skills/commands."
