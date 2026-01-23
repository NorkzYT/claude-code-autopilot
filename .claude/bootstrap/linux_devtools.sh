#!/usr/bin/env bash
set -euo pipefail

log()  { printf "\n==> %s\n" "$*"; }
skip() { printf "    [SKIP] %s\n" "$*"; }
warn() { printf "\n[WARN] %s\n" "$*" >&2; }

is_linux() { [[ "$(uname -s 2>/dev/null || echo '')" == "Linux" ]]; }
has() { command -v "$1" >/dev/null 2>&1; }

if ! is_linux; then
  warn "linux_devtools.sh is Linux-only. Skipping."
  exit 0
fi

# ---- 0) Ensure Claude Code is installed ----
if ! has claude && [[ ! -x "${HOME}/.local/bin/claude" ]]; then
  log "Installing Claude Code (native installer)..."
  curl -fsSL https://claude.ai/install.sh | bash
else
  skip "Claude Code already installed."
fi

if has claude; then
  CLAUDE_BIN="$(command -v claude)"
elif [[ -x "${HOME}/.local/bin/claude" ]]; then
  CLAUDE_BIN="${HOME}/.local/bin/claude"
else
  warn "Claude Code binary not found after install attempt. Ensure ~/.local/bin is in PATH."
  exit 1
fi

# ---- 1) Linux notifications (notify-send) ----
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
  skip "notify-send already installed."
fi

# ---- 2) Node/npm via fnm ----
setup_node_fnm() {
  if ! has fnm; then
    log "Installing fnm..."
    curl -fsSL https://fnm.vercel.app/install | bash
  else
    skip "fnm already installed."
  fi

  export PATH="$HOME/.local/share/fnm:$PATH"
  if has fnm; then
    eval "$(fnm env)"
  else
    warn "fnm not found after install; cannot proceed with Node install."
    return 1
  fi

  if ! has node; then
    log "Installing Node.js LTS..."
    INSTALL_OUT="$(fnm install lts-latest 2>&1 || true)"
    LTS_VER="$(printf '%s\n' "$INSTALL_OUT" | sed -nE 's/.*Installing Node (v[0-9]+\.[0-9]+\.[0-9]+).*/\1/p' | head -n1)"
    if [[ -n "${LTS_VER}" ]]; then
      fnm use "${LTS_VER}" || true
      fnm default "${LTS_VER}" || true
    else
      fnm use lts-latest || true
    fi
  else
    skip "Node.js already installed: $(node -v)"
  fi

  if has corepack; then
    corepack enable || true
    corepack prepare yarn@stable --activate 2>/dev/null || true
  fi
}

if ! has npm; then
  warn "npm not found. Installing Node/npm via fnm now..."
  setup_node_fnm || warn "Node/npm install failed. JS/Python LSP binaries will be skipped."
else
  skip "npm already installed: $(npm -v)"
fi

# ---- 3) Install language server binaries ----
if has npm; then
  # vtsls
  if ! has vtsls; then
    log "Installing vtsls (TypeScript/JS language server)..."
    npm i -g @vtsls/language-server typescript || warn "Failed to install vtsls/typescript via npm."
  else
    skip "vtsls already installed."
  fi

  # pyright
  if ! has pyright; then
    log "Installing pyright (Python language server)..."
    npm i -g pyright || warn "Failed to install pyright via npm."
  else
    skip "pyright already installed."
  fi
else
  warn "npm not available; skipping vtsls/pyright install."
fi

if has go; then
  if ! has gopls; then
    log "Installing gopls..."
    go install golang.org/x/tools/gopls@latest || warn "go install gopls failed."
  else
    skip "gopls already installed."
  fi
else
  skip "go not found; skipping gopls install."
fi

if has rustup; then
  if ! has rust-analyzer; then
    log "Installing rust-analyzer via rustup component..."
    rustup component add rust-analyzer || warn "rustup component add rust-analyzer failed."
  else
    skip "rust-analyzer already installed."
  fi
else
  skip "rustup not found; skipping rust-analyzer install."
fi

# ---- 4) Ensure PATH includes common install locations ----
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

log "Done."
