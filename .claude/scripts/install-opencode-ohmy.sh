#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# install-opencode-ohmy.sh
# Optional: Install OpenCode + oh-my-opencode as a SEPARATE toolchain
#
# IMPORTANT: oh-my-opencode is an OpenCode harness/plugin, NOT a Claude Code
# add-on. Its README warns about OAuth/ToS risks when used with Claude Code
# subscriptions. This script installs it as a completely separate toolchain.
#
# DO NOT merge this into your .claude/ kit.
# =============================================================================

log() { printf "\n[%s] %s\n" "$(date +%H:%M:%S)" "$*"; }
info() { printf "  -> %s\n" "$*"; }
warn() { printf "  [WARN] %s\n" "$*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"; }

show_warning() {
  cat <<'EOF'

===============================================================================
                              IMPORTANT NOTICE
===============================================================================

oh-my-opencode is designed for OpenCode, NOT Claude Code.

The oh-my-opencode README explicitly warns about OAuth/ToS implications when
used with Claude Code accounts. By proceeding, you acknowledge:

1. This installs OpenCode (a separate AI coding tool)
2. oh-my-opencode may interact with Claude APIs differently than Claude Code
3. You should review the ToS implications before using this with paid accounts

This toolchain is installed SEPARATELY from your .claude/ configuration.
It does NOT integrate with or modify your Claude Code setup.

For more information:
- OpenCode: https://opencode.ai/docs/
- oh-my-opencode: https://github.com/code-yeongyu/oh-my-opencode

===============================================================================

EOF
}

install_opencode() {
  log "Installing OpenCode..."

  if command -v opencode >/dev/null 2>&1; then
    info "OpenCode already installed: $(which opencode)"
    return
  fi

  # OpenCode official installer
  curl -fsSL https://opencode.ai/install | bash
  info "OpenCode installed successfully"
}

install_oh_my_opencode() {
  log "Installing oh-my-opencode..."

  need npm

  # Check if npx is available
  if ! command -v npx >/dev/null 2>&1; then
    die "npx not found. Install Node.js first."
  fi

  # Install oh-my-opencode
  npx oh-my-opencode@latest install

  info "oh-my-opencode installed successfully"
}

show_usage() {
  cat <<'EOF'
Usage: install-opencode-ohmy.sh [OPTIONS]

Install OpenCode + oh-my-opencode as a separate toolchain.
This is NOT integrated with Claude Code.

Options:
  --opencode-only    Install only OpenCode
  --ohmy-only        Install only oh-my-opencode (requires OpenCode)
  --yes, -y          Skip confirmation prompt
  -h, --help         Show this help

Examples:
  ./install-opencode-ohmy.sh           # Install both (with confirmation)
  ./install-opencode-ohmy.sh -y        # Install both (no confirmation)
  ./install-opencode-ohmy.sh --opencode-only   # Install OpenCode only
EOF
}

main() {
  local skip_confirm=0
  local opencode_only=0
  local ohmy_only=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --opencode-only) opencode_only=1; shift;;
      --ohmy-only)     ohmy_only=1; shift;;
      --yes|-y)        skip_confirm=1; shift;;
      -h|--help)       show_usage; exit 0;;
      *)               die "Unknown option: $1";;
    esac
  done

  show_warning

  if [[ $skip_confirm -eq 0 ]]; then
    read -rp "Do you want to proceed? [y/N] " response
    case "$response" in
      [yY][eE][sS]|[yY]) ;;
      *) echo "Aborted."; exit 0;;
    esac
  fi

  # Install components
  if [[ $ohmy_only -eq 0 ]]; then
    install_opencode
  fi

  if [[ $opencode_only -eq 0 ]]; then
    install_oh_my_opencode
  fi

  log "Installation complete."
  echo ""
  echo "To use OpenCode:"
  echo "  opencode"
  echo ""
  echo "For oh-my-opencode configuration, see:"
  echo "  https://github.com/code-yeongyu/oh-my-opencode#readme"
  echo ""
}

main "$@"
