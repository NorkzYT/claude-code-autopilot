#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# install-extras.sh
# Vendor → sync into .claude/ → keep updatable
#
# Installs curated agents, commands, skills from external repos without
# converting this kit into a plugin. Everything stays in .claude/vendor/
# (git repos) and syncs to canonical .claude/* locations.
# =============================================================================

ROOT="${1:-$(pwd)}"
CLAUDE_DIR="$ROOT/.claude"
VENDOR_DIR="$CLAUDE_DIR/vendor"

# -----------------------------------------------------------------------------
# Configuration: which plugins/agents to import
# -----------------------------------------------------------------------------
# Keep imports small + intentional (avoid tool bloat / collisions)
# Full list: https://github.com/wshobson/agents/tree/main/plugins (72 plugins)
WSHOBSON_AGENT_PLUGINS=(
  # Core workflow
  "full-stack-orchestration"
  "comprehensive-review"
  "security-scanning"
  "backend-development"

  # Language-specific
  "javascript-typescript"      # JS/TS development
  "python-development"         # Python development
  "systems-programming"        # Go, Rust, C/C++
  "jvm-languages"              # Java, Kotlin, Scala
  "functional-programming"     # Haskell, Elixir, etc.

  # Additional useful plugins
  "debugging-toolkit"
  "code-refactoring"
  "unit-testing"
  "tdd-workflows"
  "git-pr-workflows"
)

# wshobson/commands subdirs to sync
WSHOBSON_COMMAND_DIRS=(
  "tools"
  "workflows"
)

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
log() { printf "\n[%s] %s\n" "$(date +%H:%M:%S)" "$*"; }
info() { printf "  -> %s\n" "$*"; }
warn() { printf "  [WARN] %s\n" "$*" >&2; }
die() { echo "ERROR: $*" >&2; exit 1; }

need() { command -v "$1" >/dev/null 2>&1 || die "Missing dependency: $1"; }

mkdirp() { mkdir -p "$1"; }

# cross-platform sed -i
sedi() {
  if sed --version >/dev/null 2>&1; then
    sed -i "$@"
  else
    sed -i '' "$@"
  fi
}

git_clone_or_pull() {
  local url="$1" dest="$2"
  if [ -d "$dest/.git" ]; then
    info "Updating $dest ..."
    git -C "$dest" pull --ff-only 2>/dev/null || git -C "$dest" fetch --all
  else
    rm -rf "$dest"
    info "Cloning $url ..."
    git clone --depth 1 "$url" "$dest"
  fi
}

# If a name collision happens, prefix the frontmatter "name:" field so Claude sees it as unique.
# (Agents + Skills use YAML frontmatter per Claude Code docs.)
prefix_frontmatter_name_inplace() {
  local file="$1" prefix="$2"
  # replace only the first "name: xyz" occurrence
  sedi "0,/^name:[[:space:]]*/s//name: ${prefix}/" "$file" 2>/dev/null || true
}

# -----------------------------------------------------------------------------
# Installers: wshobson ecosystem
# -----------------------------------------------------------------------------
install_wshobson_commands() {
  log "Installing wshobson/commands into .claude/commands/ ..."
  mkdirp "$VENDOR_DIR"
  local repo="$VENDOR_DIR/wshobson-commands"
  git_clone_or_pull "https://github.com/wshobson/commands.git" "$repo"

  for dir in "${WSHOBSON_COMMAND_DIRS[@]}"; do
    if [ -d "$repo/$dir" ]; then
      mkdirp "$CLAUDE_DIR/commands/$dir"
      info "Syncing commands/$dir/ ..."
      rsync -a --delete "$repo/$dir/" "$CLAUDE_DIR/commands/$dir/"
    fi
  done
}

install_wshobson_agents_and_skills() {
  log "Installing curated agents + skills from wshobson/agents ..."
  mkdirp "$VENDOR_DIR"
  local repo="$VENDOR_DIR/wshobson-agents"
  git_clone_or_pull "https://github.com/wshobson/agents.git" "$repo"

  mkdirp "$CLAUDE_DIR/agents"
  mkdirp "$CLAUDE_DIR/skills"

  for plugin in "${WSHOBSON_AGENT_PLUGINS[@]}"; do
    info "Plugin: $plugin"
    local plugdir="$repo/plugins/$plugin"

    if [ ! -d "$plugdir" ]; then
      warn "Plugin directory not found: $plugdir"
      continue
    fi

    # Agents: flatten into .claude/agents/
    if [ -d "$plugdir/agents" ]; then
      for f in "$plugdir/agents/"*.md; do
        [ -e "$f" ] || continue
        local base
        base="$(basename "$f")"
        local dest="$CLAUDE_DIR/agents/$base"

        if [ -e "$dest" ]; then
          # collision: copy + prefix name field
          dest="$CLAUDE_DIR/agents/wshobson-$base"
          cp "$f" "$dest"
          prefix_frontmatter_name_inplace "$dest" "wshobson-"
          info "  Agent (prefixed): wshobson-$base"
        else
          cp "$f" "$dest"
          info "  Agent: $base"
        fi
      done
    fi

    # Skills: copy each skill directory (expects SKILL.md inside) into .claude/skills/<skill-dir>
    if [ -d "$plugdir/skills" ]; then
      for d in "$plugdir/skills/"*; do
        [ -d "$d" ] || continue

        local skill_dir
        skill_dir="$(basename "$d")"
        local dest="$CLAUDE_DIR/skills/$skill_dir"

        # Check for SKILL.md or any .md file
        if [ ! -f "$d/SKILL.md" ] && [ -z "$(find "$d" -maxdepth 1 -name '*.md' -type f 2>/dev/null | head -1)" ]; then
          continue
        fi

        if [ -e "$dest" ]; then
          dest="$CLAUDE_DIR/skills/wshobson-$skill_dir"
          rsync -a "$d/" "$dest/"
          [ -f "$dest/SKILL.md" ] && prefix_frontmatter_name_inplace "$dest/SKILL.md" "wshobson-"
          info "  Skill (prefixed): wshobson-$skill_dir"
        else
          rsync -a "$d/" "$dest/"
          info "  Skill: $skill_dir"
        fi
      done
    fi
  done
}

# -----------------------------------------------------------------------------
# Installers: standalone CLI tools (from awesome-claude-code)
# -----------------------------------------------------------------------------
install_cli_tools_info() {
  log "CLI Tools Installation Guide"
  echo ""
  echo "The following tools enhance Claude Code but install separately:"
  echo ""
  echo "1. viwo-cli (Docker sandbox + git worktrees for safe autonomous runs):"
  echo "   curl -fsSL https://raw.githubusercontent.com/OverseedAI/viwo/main/install.sh | bash"
  echo "   # Then: viwo auth; viwo register; viwo start"
  echo ""
  echo "2. run-claude-docker (single-file Docker runner):"
  echo "   curl -O https://raw.githubusercontent.com/icanhasjonas/run-claude-docker/main/run-claude.sh"
  echo "   chmod +x run-claude.sh"
  echo ""
  echo "3. recall (session memory search):"
  echo "   # macOS: brew install zippoxer/tap/recall"
  echo "   # Linux: cargo install recall-cli"
  echo ""
  echo "4. ccusage (usage telemetry):"
  echo "   npx ccusage"
  echo "   # or: brew install ryoppippi/tap/ccusage"
  echo ""
  echo "5. rulesync (config syncing across projects):"
  echo "   npm install -g rulesync"
  echo "   # or: brew install dyoshikawa/tap/rulesync"
  echo ""
  echo "6. cchooks (Python SDK for hooks):"
  echo "   pip install cchooks"
  echo ""
  echo "7. CCNotify (macOS desktop notifications):"
  echo "   # See: https://github.com/dazuiba/CCNotify"
  echo ""
}

install_viwo() {
  log "Installing viwo-cli (Docker sandbox + worktrees)..."
  if command -v viwo >/dev/null 2>&1; then
    info "viwo already installed"
    return
  fi
  curl -fsSL https://raw.githubusercontent.com/OverseedAI/viwo/main/install.sh | bash
  echo ""
  info "Run: viwo auth && viwo register && viwo start"
}

install_run_claude_docker() {
  log "Installing run-claude-docker..."
  local dest="$ROOT/scripts/run-claude.sh"
  mkdirp "$ROOT/scripts"
  curl -fsSL -o "$dest" https://raw.githubusercontent.com/icanhasjonas/run-claude-docker/main/run-claude.sh
  chmod +x "$dest"
  info "Installed to: $dest"
}

# -----------------------------------------------------------------------------
# Main entry point
# -----------------------------------------------------------------------------
show_help() {
  cat <<'EOF'
Usage: install-extras.sh [ROOT_DIR] [OPTIONS]

Install curated agents, commands, and skills from external repos into your
.claude/ directory. Everything is vendored under .claude/vendor/ and synced
to canonical locations.

Options:
  --all              Install everything (commands, agents, skills)
  --commands         Install wshobson/commands only
  --agents           Install wshobson/agents only
  --viwo             Install viwo-cli
  --docker-runner    Install run-claude-docker
  --cli-info         Show CLI tools installation guide
  --update           Update existing vendor repos (git pull)
  -h, --help         Show this help

Examples:
  ./install-extras.sh                    # Install all to current directory
  ./install-extras.sh /path/to/project   # Install all to specific project
  ./install-extras.sh --commands         # Install commands only
  ./install-extras.sh --update           # Update existing vendor repos
EOF
}

main() {
  local do_commands=0
  local do_agents=0
  local do_viwo=0
  local do_docker=0
  local do_cli_info=0
  local do_all=0

  # Parse args (skip first if it's a path)
  local args=()
  for arg in "$@"; do
    case "$arg" in
      --all)          do_all=1;;
      --commands)     do_commands=1;;
      --agents)       do_agents=1;;
      --viwo)         do_viwo=1;;
      --docker-runner) do_docker=1;;
      --cli-info)     do_cli_info=1;;
      --update)       do_all=1;;
      -h|--help)      show_help; exit 0;;
      -*)             die "Unknown option: $arg";;
      *)              args+=("$arg");;
    esac
  done

  # If no specific options, default to --all
  if [[ $do_all -eq 0 && $do_commands -eq 0 && $do_agents -eq 0 && \
        $do_viwo -eq 0 && $do_docker -eq 0 && $do_cli_info -eq 0 ]]; then
    do_all=1
  fi

  # Check dependencies
  need git
  need rsync

  mkdirp "$CLAUDE_DIR"
  mkdirp "$VENDOR_DIR"

  if [[ $do_all -eq 1 || $do_commands -eq 1 ]]; then
    install_wshobson_commands
  fi

  if [[ $do_all -eq 1 || $do_agents -eq 1 ]]; then
    install_wshobson_agents_and_skills
  fi

  if [[ $do_viwo -eq 1 ]]; then
    install_viwo
  fi

  if [[ $do_docker -eq 1 ]]; then
    install_run_claude_docker
  fi

  if [[ $do_cli_info -eq 1 ]]; then
    install_cli_tools_info
  fi

  log "Done."
  echo ""
  echo "Restart Claude Code so it re-indexes agents/skills/commands."
  echo ""
  echo "Command pack usage examples:"
  echo "  /workflows:full-stack-feature build <feature>"
  echo "  /tools:security-scan <target>"
  echo ""
  echo "To see available CLI tools: ./install-extras.sh --cli-info"
}

main "$@"
