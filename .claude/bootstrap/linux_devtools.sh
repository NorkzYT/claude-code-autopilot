#!/usr/bin/env bash
set -euo pipefail

log()  { printf "\n==> %s\n" "$*"; }
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
  log "notify-send already installed."
fi

# ---- 2) Node/npm via fnm ----
setup_node_fnm() {
  log "Installing Node.js via fnm..."
  if ! has fnm; then
    curl -fsSL https://fnm.vercel.app/install | bash
  fi

  export PATH="$HOME/.local/share/fnm:$PATH"
  if has fnm; then
    eval "$(fnm env)"
  else
    warn "fnm not found after install; cannot proceed with Node install."
    return 1
  fi

  log "Installing Node.js LTS..."
  # Works across fnm variants
  INSTALL_OUT="$(fnm install lts-latest 2>&1 || true)"
  LTS_VER="$(printf '%s\n' "$INSTALL_OUT" | sed -nE 's/.*Installing Node (v[0-9]+\.[0-9]+\.[0-9]+).*/\1/p' | head -n1)"
  if [[ -n "${LTS_VER}" ]]; then
    fnm use "${LTS_VER}" || true
    fnm default "${LTS_VER}" || true
  else
    fnm use lts-latest || true
  fi

  log "Enabling Corepack and Yarn..."
  corepack enable || true
  corepack prepare yarn@stable --activate || true

  log "Node version:"
  node -v || true
  log "npm version:"
  npm -v || true
}

if ! has npm; then
  warn "npm not found. Installing Node/npm via fnm now..."
  setup_node_fnm || warn "Node/npm install failed. JS/Python LSP binaries will be skipped."
fi

# ---- 3) Install language server binaries (match the plugins we will install) ----
if has npm; then
  log "Installing vtsls (TypeScript/JS language server) + typescript..."
  npm i -g @vtsls/language-server typescript || warn "Failed to install vtsls/typescript via npm."

  log "Installing pyright (Python language server)..."
  npm i -g pyright || warn "Failed to install pyright via npm."
else
  warn "npm not available; skipping vtsls/pyright install."
fi

if has go; then
  log "Installing gopls..."
  go install golang.org/x/tools/gopls@latest || warn "go install gopls failed."
else
  warn "go not found; skipping gopls install."
fi

if has rustup; then
  log "Installing rust-analyzer via rustup component..."
  rustup component add rust-analyzer || warn "rustup component add rust-analyzer failed."
else
  warn "rustup not found; skipping rust-analyzer install."
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

# ---- 5) Add + update the LSP marketplace that actually contains the plugins ----
add_marketplace() {
  local slug="$1"         # e.g., Piebald-AI/claude-code-lsps
  local mkt_name="$2"     # e.g., claude-code-lsps

  log "Adding marketplace '${slug}' (if missing)..."
  # Some environments fail slug-based add; HTTPS URL is the fallback.
  "${CLAUDE_BIN}" plugin marketplace add "${slug}" >/dev/null 2>&1 \
    || "${CLAUDE_BIN}" plugin marketplace add "https://github.com/${slug}.git" >/dev/null 2>&1 \
    || warn "Failed to add marketplace '${slug}'. You may need to add it inside Claude with: /plugin marketplace add ${slug}"

  log "Updating marketplace '${mkt_name}'..."
  "${CLAUDE_BIN}" plugin marketplace update "${mkt_name}" >/dev/null 2>&1 \
    || warn "Marketplace update failed for '${mkt_name}'."
}

install_plugin() {
  local plugin="$1"
  local marketplace="$2"
  log "Installing plugin '${plugin}@${marketplace}'..."
  "${CLAUDE_BIN}" plugin install "${plugin}@${marketplace}" --scope user >/dev/null 2>&1 \
    && log "Installed: ${plugin}@${marketplace}" \
    || warn "Failed: ${plugin}@${marketplace}"
}

# Piebald marketplace: provides vtsls/pyright/gopls/rust-analyzer plugins
add_marketplace "Piebald-AI/claude-code-lsps" "claude-code-lsps"

log "Installing Claude Code LSP plugins (user scope)..."
install_plugin "vtsls" "claude-code-lsps"
install_plugin "pyright" "claude-code-lsps"
install_plugin "gopls" "claude-code-lsps"
install_plugin "rust-analyzer" "claude-code-lsps"

log "Done."
log "If LSP features still show as unavailable, you may need to enable the built-in LSP tool for your Claude Code version: export ENABLE_LSP_TOOL=1"
