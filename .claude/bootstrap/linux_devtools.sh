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

# Avoid running node/npm installs as root (permission hell)
if [[ "$(id -u)" -eq 0 ]]; then
  warn "Running as root. For best results, run bootstrap as a normal user (installer should su to TARGET_USER)."
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

# ---- 2) Node/npm via fnm (your requested approach) ----
setup_node_fnm() {
  log "Installing Node.js via fnm..."
  if ! has fnm; then
    curl -fsSL https://fnm.vercel.app/install | bash
  fi

  # Make fnm available in this script run
  export PATH="$HOME/.local/share/fnm:$PATH"
  if has fnm; then
    # shellcheck disable=SC1090
    eval "$(fnm env)"
  else
    warn "fnm not found after install; cannot proceed with Node install."
    return 1
  fi

  log "Installing Node.js LTS..."
  fnm install --lts || true
  fnm use --lts || true

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
  setup_node_fnm || warn "Node/npm install failed. TS/Pyright language servers will be skipped."
fi

# ---- 3) Install language server binaries ----
# Official docs: LSP plugins require the language server binary in PATH. :contentReference[oaicite:3]{index=3}

if has npm; then
  log "Installing TypeScript language server..."
  npm i -g typescript typescript-language-server || warn "Failed to install TypeScript language server via npm."
  log "Installing Pyright (pyright-langserver)..."
  npm i -g pyright || warn "Failed to install pyright via npm."
else
  warn "npm not available; skipping TypeScript/Pyright language server install."
fi

if has go; then
  log "Installing gopls..."
  # gopls may require Go 1.25+ now; Go 1.21+ will auto-fetch toolchain. :contentReference[oaicite:4]{index=4}
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

# ---- 4) Ensure PATH includes common install locations (best-effort) ----
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

# ---- 5) Install Claude Code LSP plugins ----
# Official docs say the official marketplace is `claude-plugins-official`. :contentReference[oaicite:5]{index=5}
# But Anthropic’s directory repo also references `@claude-plugin-directory`. :contentReference[oaicite:6]{index=6}
# So we try multiple marketplace ids for compatibility.

maybe_marketplace_update() {
  local m="$1"
  # Some builds expose marketplace update via CLI, some don't; try and ignore if unsupported.
  "${CLAUDE_BIN}" plugin marketplace update "$m" >/dev/null 2>&1 || true
}

install_plugin_try() {
  local plugin="$1"
  local marketplace="$2"
  local scope="$3"

  "${CLAUDE_BIN}" plugin install "${plugin}@${marketplace}" --scope "${scope}" >/dev/null 2>&1
}

install_plugin_any_marketplace() {
  local plugin="$1"
  local scope="$2"
  shift 2
  local marketplaces=("$@")

  for m in "${marketplaces[@]}"; do
    maybe_marketplace_update "$m"
    log "Installing plugin '${plugin}' from marketplace '${m}'..."
    if install_plugin_try "$plugin" "$m" "$scope"; then
      log "Installed: ${plugin}@${m}"
      return 0
    fi
  done

  warn "Failed to install '${plugin}' from any known marketplace."
  return 1
}

MARKETPLACES=("claude-plugins-official" "claude-plugin-directory" "anthropics-claude-plugins-official")

log "Installing Claude Code LSP plugins (user scope)..."
install_plugin_any_marketplace "typescript-lsp" "user" "${MARKETPLACES[@]}" || true
install_plugin_any_marketplace "pyright-lsp" "user" "${MARKETPLACES[@]}" || true
install_plugin_any_marketplace "gopls-lsp" "user" "${MARKETPLACES[@]}" || true

# Rust plugin naming varies by docs/version; try both. :contentReference[oaicite:7]{index=7}
install_plugin_any_marketplace "rust-analyzer-lsp" "user" "${MARKETPLACES[@]}" || true
install_plugin_any_marketplace "rust-lsp" "user" "${MARKETPLACES[@]}" || true

log "Done."
log "If LSP tools still don’t appear: open Claude Code and run '/plugin marketplace update claude-plugins-official', then restart Claude Code." :contentReference[oaicite:8]{index=8}
