#!/usr/bin/env bash
set -euo pipefail

log() { printf "\n==> %s\n" "$*"; }
warn() { printf "\n[WARN] %s\n" "$*" >&2; }

is_linux() { [[ "$(uname -s 2>/dev/null || echo '')" == "Linux" ]]; }
has() { command -v "$1" >/dev/null 2>&1; }

if ! is_linux; then
  warn "linux_devtools.sh is Linux-only. Skipping."
  exit 0
fi

# --- 0) Install Claude Code (native installer) if missing ---
if ! has claude && [[ ! -x "${HOME}/.local/bin/claude" ]]; then
  log "Installing Claude Code (native installer)..."
  # Official install method 
  curl -fsSL https://claude.ai/install.sh | bash
fi

# Resolve claude path (native installer often puts it in ~/.local/bin) 
if has claude; then
  CLAUDE_BIN="$(command -v claude)"
elif [[ -x "${HOME}/.local/bin/claude" ]]; then
  CLAUDE_BIN="${HOME}/.local/bin/claude"
else
  warn "Claude Code binary not found after install attempt. Ensure ~/.local/bin is in PATH."
  exit 1
fi

# --- 1) Linux notifications (notify-send) ---
if ! has notify-send; then
  if has apt-get; then
    log "Installing notify-send (libnotify-bin) via apt-get..."
    if [[ "$(id -u)" -eq 0 ]]; then
      apt-get update
      apt-get install -y libnotify-bin
    else
      sudo apt-get update
      sudo apt-get install -y libnotify-bin
    fi
  else
    warn "apt-get not found. Install notify-send manually (package is typically 'libnotify-bin')."
  fi
else
  log "notify-send already installed."
fi

# --- 2) Install language server binaries (best-effort) ---
# Note: Claude Code docs advise against sudo npm global installs due to permissions issues.
if has npm; then
  log "Installing TypeScript language server..."
  npm i -g typescript typescript-language-server || warn "npm global install failed. Consider using nvm / user-level npm prefix."
  log "Installing Pyright..."
  npm i -g pyright || warn "npm global install failed. Consider using nvm / user-level npm prefix."
else
  warn "npm not found. Skipping TypeScript/Pyright language server install."
fi

if has go; then
  log "Installing gopls..."
  go install golang.org/x/tools/gopls@latest || warn "go install gopls failed."
else
  warn "go not found. Skipping gopls install."
fi

if has rustup; then
  log "Installing rust-analyzer via rustup component..."
  rustup component add rust-analyzer || warn "rustup component add rust-analyzer failed."
else
  warn "rustup not found. Skipping rust-analyzer install."
fi

# --- 3) PATH hints (for THIS script run) ---
# Claude Code LSP plugins depend on language server binaries being discoverable in PATH. 
if has npm; then
  NPM_PREFIX="$(npm config get prefix 2>/dev/null || true)"
  if [[ -n "${NPM_PREFIX}" && -d "${NPM_PREFIX}/bin" ]]; then
    export PATH="${NPM_PREFIX}/bin:${PATH}"
  fi
fi
if has go; then
  GOPATH_BIN="$(go env GOPATH 2>/dev/null)/bin"
  if [[ -d "${GOPATH_BIN}" ]]; then
    export PATH="${GOPATH_BIN}:${PATH}"
  fi
fi
if [[ -d "${HOME}/.cargo/bin" ]]; then
  export PATH="${HOME}/.cargo/bin:${PATH}"
fi

# --- 4) Install Claude Code LSP plugins (official marketplace) ---
# Official marketplace is available automatically 
# Non-interactive plugin install CLI is supported 
log "Installing Claude Code LSP plugins (user scope)..."
"${CLAUDE_BIN}" plugin install "typescript-lsp@claude-plugins-official" --scope user || warn "typescript-lsp install failed."
"${CLAUDE_BIN}" plugin install "pyright-lsp@claude-plugins-official" --scope user || warn "pyright-lsp install failed."
"${CLAUDE_BIN}" plugin install "gopls-lsp@claude-plugins-official" --scope user || warn "gopls-lsp install failed."
"${CLAUDE_BIN}" plugin install "rust-analyzer-lsp@claude-plugins-official" --scope user || warn "rust-analyzer-lsp install failed."

log "Done."
log "Note: Some Claude Code builds gate the LSP tool behind ENABLE_LSP_TOOL=1 for runtime usage (set in your shell env before running 'claude')."

# Heads-up: there have been reports of broken/incomplete official LSP plugins in some versions.
