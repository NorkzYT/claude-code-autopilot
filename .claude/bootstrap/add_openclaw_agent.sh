#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────
# add_openclaw_agent.sh — Register any project as an OpenClaw agent
#
# Usage:
#   bash .claude/bootstrap/add_openclaw_agent.sh <agent-name> <workspace-path> [options]
#
# Options:
#   --name <display-name>     Display name (default: capitalized agent-name)
#   --emoji <emoji>           Agent emoji (default: 🔧)
#   --force                   Overwrite existing persona .md files with latest templates
#   --skip-persona            Don't create persona files
#   --skip-skills             Don't create skills/ directory
#   --skip-codex              Don't create Codex compatibility files
#   --no-restart              Don't restart the gateway
#   --tool-access <mode>      Tool access profile: minimal|coding|messaging|full|inherit (default: full)
#
# Example:
#   bash .claude/bootstrap/add_openclaw_agent.sh myproject /opt/github/MyProject --name "My Project" --emoji "🔧"
# ─────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$(cd "$SCRIPT_DIR/../templates/agent-persona" && pwd 2>/dev/null || echo "")"
CODEX_TEMPLATE_DIR="$(cd "$SCRIPT_DIR/../templates/codex" && pwd 2>/dev/null || echo "")"
GIT_HOOK_TEMPLATE_DIR="$(cd "$SCRIPT_DIR/../templates/git-hooks" && pwd 2>/dev/null || echo "")"
# OpenClaw uses OPENCLAW_STATE_DIR for the state root. Prefer it and avoid
# relying on OPENCLAW_HOME here because some setups export it with a different
# meaning, which can cause nested ~/.openclaw/.openclaw paths.
OPENCLAW_HOME="${OPENCLAW_STATE_DIR:-${OPENCLAW_HOME:-$HOME/.openclaw}}"

# ─── Defaults ───────────────────────────────────────────────
DISPLAY_NAME=""
EMOJI="🔧"
SKIP_PERSONA=false
SKIP_SKILLS=false
SKIP_CODEX=false
NO_RESTART=false
FORCE_OVERWRITE="${OPENCLAW_FORCE:-false}"
TOOL_ACCESS_PROFILE="${OPENCLAW_TOOL_ACCESS:-full}"
TOOL_ACCESS_PROFILE_SPECIFIED=false

# ─── Helpers ────────────────────────────────────────────────
log()  { echo "  [+] $*"; }
warn() { echo "  [!] $*" >&2; }
err()  { echo "  [ERROR] $*" >&2; exit 1; }
skip() { echo "  [~] $* (already exists, skipping)"; }
has()  { command -v "$1" >/dev/null 2>&1; }

restart_openclaw_gateway() {
  # Check if openclaw-gateway container is running (Docker setup)
  if has docker && docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^openclaw-gateway$'; then
    log "Detected Docker setup - restarting via docker compose..."

    # Find docker-compose file (check common locations)
    local compose_file=""
    for dir in "." ".." "../.." "../../.." "../../../.."; do
      if [[ -f "$dir/docker-compose.openclaw.yml" ]]; then
        compose_file="$dir/docker-compose.openclaw.yml"
        break
      fi
    done

    if [[ -n "$compose_file" ]]; then
      docker compose -f "$compose_file" restart openclaw-gateway 2>&1
      return $?
    else
      warn "Docker container found but docker-compose.openclaw.yml not found. Trying standard restart..."
    fi
  fi

  # Fallback to standard restart methods
  openclaw gateway restart 2>&1
}

gateway_status_ready() {
  local out
  out="$(openclaw gateway status 2>&1 || true)"
  echo "$out" | grep -q "RPC probe: ok" && echo "$out" | grep -q "^Listening:"
}

wait_for_gateway_ready() {
  local timeout_secs="${1:-20}"
  local elapsed=0
  while (( elapsed < timeout_secs )); do
    if gateway_status_ready; then
      return 0
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done
  return 1
}

ensure_gitignore_entry() {
  local file="$1"
  local entry="$2"
  if grep -qF "$entry" "$file" 2>/dev/null; then
    return 1
  fi
  printf '%s\n' "$entry" >> "$file"
  return 0
}

install_commit_msg_hook() {
  local workspace="$1"
  local hook_template="$GIT_HOOK_TEMPLATE_DIR/commit-msg-no-coauthors.sh"
  local git_dir="$workspace/.git"
  local hooks_dir="$git_dir/hooks"
  local hook_path="$hooks_dir/commit-msg"
  local managed_marker="commit-msg-no-coauthors (managed by add_openclaw_agent.sh)"

  if [[ ! -d "$git_dir" ]]; then
    warn "No .git directory found; skipping commit-msg hook installation"
    return 1
  fi

  mkdir -p "$hooks_dir"

  if [[ -f "$hook_path" ]] && ! grep -q "$managed_marker" "$hook_path" 2>/dev/null; then
    warn "Existing commit-msg hook detected (unmanaged). Skipping overwrite."
    warn "Manually add Co-Authored-By blocking or merge with $hook_template"
    return 1
  fi

  if [[ -f "$hook_template" ]]; then
    cp "$hook_template" "$hook_path"
  else
    cat > "$hook_path" << 'HOOKEOF'
#!/usr/bin/env bash
# commit-msg-no-coauthors (managed by add_openclaw_agent.sh)
set -euo pipefail
MSG_FILE="${1:-}"
if [[ -n "$MSG_FILE" && -f "$MSG_FILE" ]] && grep -Eiq '^[[:space:]]*Co-Authored-By:' "$MSG_FILE"; then
  echo "ERROR: Commit message contains Co-Authored-By trailer. Remove it and retry." >&2
  exit 1
fi
HOOKEOF
  fi

  chmod +x "$hook_path" 2>/dev/null || true
  log "Installed .git/hooks/commit-msg (blocks Co-Authored-By trailers)"
  return 0
}

usage() {
  echo "Usage: bash $0 <agent-name> <workspace-path> [options]"
  echo ""
  echo "Options:"
  echo "  --name <display-name>     Display name (default: capitalized agent-name)"
  echo "  --emoji <emoji>           Agent emoji (default: 🔧)"
  echo "  --force                   Overwrite existing persona .md files with latest templates"
  echo "  --skip-persona            Don't create persona files"
  echo "  --skip-skills             Don't create skills/ directory"
  echo "  --skip-codex              Don't create Codex compatibility files"
  echo "  --no-restart              Don't restart the gateway"
  echo "  --tool-access <mode>      Tool access profile: minimal|coding|messaging|full|inherit (default: full)"
  exit 1
}

capitalize() {
  echo "$1" | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}'
}

# ─── Parse Arguments ────────────────────────────────────────
[[ $# -lt 2 ]] && usage

AGENT_NAME="$1"
WORKSPACE_PATH="$2"
shift 2

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)       DISPLAY_NAME="$2"; shift 2 ;;
    --emoji)      EMOJI="$2"; shift 2 ;;
    --skip-persona) SKIP_PERSONA=true; shift ;;
    --skip-skills)  SKIP_SKILLS=true; shift ;;
    --skip-codex)   SKIP_CODEX=true; shift ;;
    --no-restart)   NO_RESTART=true; shift ;;
    --tool-access)
      TOOL_ACCESS_PROFILE="$2"
      TOOL_ACCESS_PROFILE_SPECIFIED=true
      shift 2
      ;;
    --force)        FORCE_OVERWRITE=1; shift ;;
    -h|--help)    usage ;;
    *)            err "Unknown option: $1" ;;
  esac
done

if [[ "$TOOL_ACCESS_PROFILE_SPECIFIED" == "false" ]] && [[ -t 0 ]]; then
  read -rp "Tool access profile [minimal/coding/messaging/full/inherit] (default: full): " TOOL_ACCESS_ANS
  TOOL_ACCESS_PROFILE="${TOOL_ACCESS_ANS:-$TOOL_ACCESS_PROFILE}"
fi

case "$TOOL_ACCESS_PROFILE" in
  minimal|coding|messaging|full|inherit) ;;
  *) err "Invalid --tool-access value '$TOOL_ACCESS_PROFILE'. Use: minimal|coding|messaging|full|inherit" ;;
esac

# ─── Section 0: Validation ──────────────────────────────────
echo ""
echo "======================================"
echo "  OpenClaw Agent Registration"
echo "======================================"
echo ""

# Validate agent name (lowercase, alphanumeric + hyphens)
if ! [[ "$AGENT_NAME" =~ ^[a-z][a-z0-9-]*$ ]]; then
  err "Agent name must be lowercase alphanumeric with hyphens (e.g., 'my-agent')"
fi

# Validate workspace exists
if [[ ! -d "$WORKSPACE_PATH" ]]; then
  err "Workspace directory does not exist: $WORKSPACE_PATH"
fi

# Resolve absolute path
WORKSPACE_PATH="$(cd "$WORKSPACE_PATH" && pwd)"

# Set display name default
[[ -z "$DISPLAY_NAME" ]] && DISPLAY_NAME="$(capitalize "$AGENT_NAME")"

# Check openclaw CLI
if ! command -v openclaw &>/dev/null; then
  err "openclaw CLI not found. Install with: npm install -g openclaw@latest"
fi

# Check template directory
if [[ -z "$TEMPLATE_DIR" ]] || [[ ! -d "$TEMPLATE_DIR" ]]; then
  warn "Template directory not found at .claude/templates/agent-persona/"
  warn "Persona files will not be created."
  SKIP_PERSONA=true
fi

log "Agent name:    $AGENT_NAME"
log "Display name:  $DISPLAY_NAME"
log "Workspace:     $WORKSPACE_PATH"
log "Emoji:         $EMOJI"
if [[ "$TOOL_ACCESS_PROFILE" == "inherit" ]]; then
  log "Tool access:   inherit (no per-agent override)"
else
  log "Tool access:   $TOOL_ACCESS_PROFILE (per-agent override)"
fi
echo ""

# ─── Section 1: Register Agent ──────────────────────────────
log "Section 1: Registering agent..."

AGENT_EXISTS=false
if openclaw agents list --json 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    agents = data if isinstance(data, list) else data.get('agents', [])
    names = [a.get('name', '') for a in agents]
    sys.exit(0 if '$AGENT_NAME' in names else 1)
except:
    sys.exit(1)
" 2>/dev/null; then
  AGENT_EXISTS=true
  skip "Agent '$AGENT_NAME' already registered"
else
  if openclaw agents add "$AGENT_NAME" --workspace "$WORKSPACE_PATH" --non-interactive 2>/dev/null; then
    log "Agent '$AGENT_NAME' registered successfully"
  else
    warn "openclaw agents add failed — will configure manually"
  fi
fi

# ─── Section 2: Copy Auth ───────────────────────────────────
log "Section 2: Copying authentication..."

AGENT_DIR="$OPENCLAW_HOME/agents/$AGENT_NAME"
mkdir -p "$AGENT_DIR"

# Find a source agent directory with auth files
AUTH_SOURCE=""
if [[ -d "$OPENCLAW_HOME/agents" ]]; then
  for dir in "$OPENCLAW_HOME/agents"/*/; do
    [[ "$(basename "$dir")" == "$AGENT_NAME" ]] && continue
    if [[ -f "${dir}auth.json" ]]; then
      AUTH_SOURCE="$dir"
      break
    fi
  done
fi

if [[ -n "$AUTH_SOURCE" ]]; then
  for auth_file in auth.json auth-profiles.json; do
    if [[ -f "$AUTH_SOURCE/$auth_file" ]] && [[ ! -f "$AGENT_DIR/$auth_file" ]]; then
      cp "$AUTH_SOURCE/$auth_file" "$AGENT_DIR/$auth_file"
      log "Copied $auth_file from $(basename "$AUTH_SOURCE")"
    elif [[ -f "$AGENT_DIR/$auth_file" ]]; then
      skip "$auth_file already exists in agent directory"
    fi
  done
else
  warn "No existing agent with auth files found. You'll need to authenticate manually:"
  warn "  openclaw models auth paste-token --provider anthropic --agent $AGENT_NAME"
fi

# ─── Section 3: Config Sync ─────────────────────────────────
log "Section 3: Syncing configuration..."

# Use a single canonical config path.
CONFIG_PATHS=(
  "$OPENCLAW_HOME/openclaw.json"
)

for config_path in "${CONFIG_PATHS[@]}"; do
  if [[ ! -f "$config_path" ]]; then
    mkdir -p "$(dirname "$config_path")"
    echo '{}' > "$config_path"
    log "Created config: $config_path"
  fi

  # Ensure current OpenClaw config schema and the agent entry exist.
  config_result="$(python3 - "$config_path" "$AGENT_NAME" "$DISPLAY_NAME" "$WORKSPACE_PATH" "$EMOJI" "$TOOL_ACCESS_PROFILE" <<'PY' 2>/dev/null
import json
import sys
from pathlib import Path

config_path, agent_name, display_name, workspace_path, emoji, tool_access_profile = sys.argv[1:]
p = Path(config_path)

try:
    data = json.loads(p.read_text()) if p.exists() else {}
except Exception:
    data = {}

if not isinstance(data, dict):
    data = {}

agents = data.get("agents")
if not isinstance(agents, dict):
    agents = {}

agent_list = agents.get("list")
if not isinstance(agent_list, list):
    agent_list = []

exists = False

def apply_tool_access(entry: dict) -> None:
    if tool_access_profile == "inherit":
        tools = entry.get("tools")
        if isinstance(tools, dict):
            tools.pop("profile", None)
            if not tools:
                entry.pop("tools", None)
        else:
            entry.pop("tools", None)
        return
    tools = entry.get("tools")
    if not isinstance(tools, dict):
        tools = {}
    tools["profile"] = tool_access_profile
    entry["tools"] = tools

for entry in agent_list:
    if not isinstance(entry, dict):
        continue
    entry.pop("displayName", None)
    entry.pop("emoji", None)
    if entry.get("name") == agent_name or entry.get("id") == agent_name:
        exists = True
        apply_tool_access(entry)

if not exists:
    config_root = p.parent
    new_entry = {
        "id": agent_name,
        "name": agent_name,
        "workspace": workspace_path,
        "agentDir": str(config_root / "agents" / agent_name / "agent")
    }
    apply_tool_access(new_entry)
    agent_list.append(new_entry)

agents["list"] = agent_list
data["agents"] = agents

p.write_text(json.dumps(data, indent=2) + "\n")
if exists:
    print("exists")
else:
    print("added")
PY
)"

  case "$config_result" in
    exists)
      skip "Agent already in $(basename "$(dirname "$config_path")")/$(basename "$config_path")"
      ;;
    added)
      log "Added agent to $(basename "$(dirname "$config_path")")/$(basename "$config_path")"
      ;;
    *)
      warn "Failed to update $config_path"
      ;;
  esac

  if [[ "$TOOL_ACCESS_PROFILE" == "inherit" ]]; then
    log "Agent tool access in $(basename "$config_path"): inherit (uses global tools.profile)"
  else
    log "Agent tool access in $(basename "$config_path"): $TOOL_ACCESS_PROFILE"
  fi
done

# ─── Section 4: Create Persona Files ────────────────────────
if [[ "$SKIP_PERSONA" == "false" ]]; then
  log "Section 4: Creating persona files..."

  # Ensure runtime directory exists (sessions, memory notes, reports, skills)
  mkdir -p "$WORKSPACE_PATH/.openclaw"

  for tmpl in "$TEMPLATE_DIR"/*.tmpl; do
    [[ ! -f "$tmpl" ]] && continue
    filename="$(basename "$tmpl" .tmpl)"
    # Analyzer owns these files so they always reflect the actual repo, not
    # generic template content.
    case "$filename" in
      TOOLS.md|HEARTBEAT.md|PROJECT.md)
        continue
        ;;
    esac
    target="$WORKSPACE_PATH/$filename"

    if [[ -f "$target" ]] && [[ "$FORCE_OVERWRITE" != "1" ]]; then
      skip "$filename"
      continue
    fi

    sed \
      -e "s|{{AGENT_NAME}}|$AGENT_NAME|g" \
      -e "s|{{DISPLAY_NAME}}|$DISPLAY_NAME|g" \
      -e "s|{{WORKSPACE_PATH}}|$WORKSPACE_PATH|g" \
      -e "s|{{EMOJI}}|$EMOJI|g" \
      "$tmpl" > "$target"
    if [[ "$FORCE_OVERWRITE" == "1" ]]; then
      log "Updated $filename (--force)"
    else
      log "Created $filename"
    fi
  done
  # Inject autopilot skills section into existing AGENTS.md if missing.
  # This ensures existing workspaces get the pipeline on re-runs.
  AGENTS_FILE="$WORKSPACE_PATH/AGENTS.md"
  if [[ -f "$AGENTS_FILE" ]] && ! grep -q "Autopilot Workflow" "$AGENTS_FILE" 2>/dev/null; then
    AUTOPILOT_BLOCK='
## Autopilot Workflow (Mandatory for All Coding Tasks)

**YOUR FIRST LINE FOR ANY CODING TASK MUST BE:**
```
**Triage:** Simple/Medium/Complex, <file count> files -- <brief description>
```

**Then output each subsequent step header before executing it:**
- **Plan:** <numbered list>
- **Implement:** <as you code>
- **Verify:** <build/test results>
- **Commit:** <commit hash>
- **Report:** <summary>

**IMPORTANT: This is NOT optional guidance. You MUST output these headers. Follow this pipeline automatically for EVERY coding task. Do not wait for the user to ask.**

### Step 1: Triage
- Classify: **Simple** (1-2 files) / **Medium** (3-4 files) / **Complex** (4+ files, architectural)
- Complex tasks → escalate to Opus via `autopilot-opus` subagent
- For tasks expected to take >5 min: create `/recheckin` cron FIRST, include job ID in message

### Step 2: Plan
- Write a short plan (3-10 lines) before implementing
- Identify files to change, dependencies, and risk areas

### Step 3: Implement
- Read before writing. Follow existing patterns. Smallest change possible.
- Quality: SOLID, DRY, KISS, Separation of Concerns
- For each edit: Reason → Act → Observe (re-read file after editing) → Repeat if mismatch

### Step 4: Verify
- Re-read EVERY changed file after editing
- Run build command from TOOLS.md
- Run test command from TOOLS.md
- 4+ files changed → run self-review checklist (missed edge cases, naming, error handling)

### Step 5: Commit
- Conventional format: `type(scope): description`
- Feature branch only. Never commit untested code.
- NEVER include `Co-Authored-By` in commit messages.

### Step 6: Report
- What changed (bullets), files modified, test results, status

### Session Health
- After 20-25 coding turns: write checkpoint to `memory/YYYY-MM-DD.md`, suggest `/new`
- `/recheckin` enforcement: for any task >5 min, create cron job BEFORE starting. Include job ID or state CLI did not return one.

For detailed reference, read the skill files: `autopilot-workflow`, `quality-gates`, `model-router`, `session-hygiene`'

    # Inject before "## Safety" or append at end
    if grep -q "^## Safety" "$AGENTS_FILE" 2>/dev/null; then
      python3 -c "
import sys
content = open('$AGENTS_FILE').read()
block = '''$AUTOPILOT_BLOCK'''
content = content.replace('## Safety', block.strip() + '\n\n## Safety', 1)
open('$AGENTS_FILE', 'w').write(content)
" 2>/dev/null && log "Injected autopilot skills into existing AGENTS.md" || true
    else
      printf '\n%s\n' "$AUTOPILOT_BLOCK" >> "$AGENTS_FILE"
      log "Appended autopilot skills to existing AGENTS.md"
    fi
  fi

else
  log "Section 4: Skipping persona files (--skip-persona)"
fi

# ─── Section 4d: Auto-discover project ────────────────────
log "Section 4d: Analyzing project..."

ANALYZE_SCRIPT="$SCRIPT_DIR/analyze_repo.sh"
if [[ -f "$ANALYZE_SCRIPT" ]]; then
  log "Phase A: Static repo analysis..."
  bash "$ANALYZE_SCRIPT" "$WORKSPACE_PATH"

  log "Phase B: Deep codebase understanding (Claude scan)..."
  if command -v claude &>/dev/null; then
    bash "$ANALYZE_SCRIPT" "$WORKSPACE_PATH" --deep
  else
    warn "Claude CLI not found — skipping deep analysis"
    warn "Run manually: bash $ANALYZE_SCRIPT $WORKSPACE_PATH --deep"
  fi
else
  warn "analyze_repo.sh not found — skipping project analysis"
fi

# ─── Section 4e: Link sessions into workspace ─────────────────
log "Section 4e: Linking sessions into workspace..."

WORKSPACE_SESSIONS="$WORKSPACE_PATH/.openclaw/sessions"
mkdir -p "$WORKSPACE_SESSIONS"

# Link from both OpenClaw state directories
for state_dir in "$OPENCLAW_HOME/agents/$AGENT_NAME" "$OPENCLAW_HOME/.openclaw/agents/$AGENT_NAME"; do
  if [[ -d "$state_dir/sessions" && ! -L "$state_dir/sessions" ]]; then
    # Copy existing sessions into workspace (no-clobber to avoid overwriting)
    cp -n "$state_dir/sessions/"* "$WORKSPACE_SESSIONS/" 2>/dev/null || true
    # Handle sessions.json conflicts: keep larger file, rename smaller to sessions-alt.json
    if [[ -f "$WORKSPACE_SESSIONS/sessions.json" ]] && [[ -f "$state_dir/sessions/sessions.json" ]]; then
      ws_size="$(stat -c%s "$WORKSPACE_SESSIONS/sessions.json" 2>/dev/null || echo 0)"
      src_size="$(stat -c%s "$state_dir/sessions/sessions.json" 2>/dev/null || echo 0)"
      if [[ "$src_size" -gt "$ws_size" ]]; then
        # Source is larger — save workspace version as alt, use source version
        mv "$WORKSPACE_SESSIONS/sessions.json" "$WORKSPACE_SESSIONS/sessions-alt.json" 2>/dev/null || true
        cp "$state_dir/sessions/sessions.json" "$WORKSPACE_SESSIONS/sessions.json"
      fi
    fi
    # Back up original dir and replace with symlink
    mv "$state_dir/sessions" "$state_dir/sessions.bak"
    ln -s "$WORKSPACE_SESSIONS" "$state_dir/sessions"
    log "Linked $state_dir/sessions -> $WORKSPACE_SESSIONS"
  elif [[ -L "$state_dir/sessions" ]]; then
    skip "sessions already symlinked in $(basename "$(dirname "$state_dir")")"
  fi
done

# Ensure local agent/runtime state is gitignored in workspace
GITIGNORE="$WORKSPACE_PATH/.gitignore"
if [[ ! -f "$GITIGNORE" ]]; then
  touch "$GITIGNORE"
  log "Created .gitignore"
fi

if ensure_gitignore_entry "$GITIGNORE" ""; then :; fi
if ensure_gitignore_entry "$GITIGNORE" "# Local agent runtime state (OpenClaw + Claude + Codex)"; then :; fi
if ensure_gitignore_entry "$GITIGNORE" ".claude/"; then :; fi
if ensure_gitignore_entry "$GITIGNORE" ".codex/"; then :; fi
if ensure_gitignore_entry "$GITIGNORE" ".codex-home/"; then :; fi
if ensure_gitignore_entry "$GITIGNORE" ".agents/"; then :; fi
if ensure_gitignore_entry "$GITIGNORE" ".openclaw/"; then :; fi
if ensure_gitignore_entry "$GITIGNORE" ".openclaw/sessions/"; then :; fi
if ensure_gitignore_entry "$GITIGNORE" "AGENTS.md"; then :; fi
if ensure_gitignore_entry "$GITIGNORE" "SOUL.md"; then :; fi
if ensure_gitignore_entry "$GITIGNORE" "USER.md"; then :; fi
if ensure_gitignore_entry "$GITIGNORE" "IDENTITY.md"; then :; fi
if ensure_gitignore_entry "$GITIGNORE" "TOOLS.md"; then :; fi
if ensure_gitignore_entry "$GITIGNORE" "HEARTBEAT.md"; then :; fi
if ensure_gitignore_entry "$GITIGNORE" "BOOTSTRAP.md"; then :; fi
if ensure_gitignore_entry "$GITIGNORE" "MEMORY.md"; then :; fi
if ensure_gitignore_entry "$GITIGNORE" "memory/"; then :; fi
if ensure_gitignore_entry "$GITIGNORE" "PROJECT.md"; then :; fi

if grep -qF "# Local agent runtime state (OpenClaw + Claude + Codex)" "$GITIGNORE" 2>/dev/null; then
  log "Ensured .gitignore entries for .claude/.codex/.codex-home/.agents/.openclaw and root OpenClaw core files"
fi

# ─── Section 4b: Create Guard Hooks ─────────────────────────
log "Section 4b: Creating safety guard hooks..."

WORKSPACE_CLAUDE_DIR="$WORKSPACE_PATH/.claude"
WORKSPACE_HOOKS_DIR="$WORKSPACE_CLAUDE_DIR/hooks"
mkdir -p "$WORKSPACE_HOOKS_DIR"

# Copy guard_bash.py from our hooks
GUARD_SOURCE="$SCRIPT_DIR/../hooks/guard_bash_workspace.py"
GUARD_TARGET="$WORKSPACE_HOOKS_DIR/guard_bash.py"

if [[ -f "$GUARD_TARGET" ]]; then
  skip "guard_bash.py hook"
else
  if [[ -f "$GUARD_SOURCE" ]]; then
    cp "$GUARD_SOURCE" "$GUARD_TARGET"
    log "Copied guard_bash.py to workspace"
  else
    # Generate a minimal guard hook inline
    cat > "$GUARD_TARGET" << 'GUARDHOOK'
#!/usr/bin/env python3
"""Guard hook for OpenClaw agent workspace — blocks dangerous commands."""
import json, re, sys

def main():
    try:
        event = json.load(sys.stdin)
    except (json.JSONDecodeError, EOFError):
        print(json.dumps({"decision": "allow"}))
        return

    tool_name = event.get("tool_name", "")
    if tool_name == "Bash":
        cmd = event.get("tool_input", {}).get("command", "")
        blocked = [
            (r"\brm\s+", "rm command blocked"),
            (r"\brm\b", "rm command blocked"),
            (r"\bsudo\b", "sudo blocked"),
            (r"\|\s*(bash|sh|zsh|python)", "pipe to shell blocked"),
            (r"git\s+push\s+.*--force", "force push blocked"),
            (r"git\s+push\s+.*-f\b", "force push blocked"),
            (r"git\s+push\s+.*\b(main|master)\b", "push to main/master blocked"),
            (r"\bshred\b", "shred blocked"),
            (r"\bdd\s+", "dd blocked"),
            (r"\breboot\b", "reboot blocked"),
            (r"\bshutdown\b", "shutdown blocked"),
        ]
        for pattern, reason in blocked:
            if re.search(pattern, cmd, re.IGNORECASE):
                print(json.dumps({"decision": "block", "reason": reason}))
                return
    elif tool_name == "Write":
        fp = event.get("tool_input", {}).get("file_path", "")
        content = event.get("tool_input", {}).get("content", "")
        if fp.endswith(('.py', '.sh', '.bash', '.rb', '.pl')):
            for p, r in [
                (r"\bos\.remove\b", "os.remove in script"),
                (r"\bos\.unlink\b", "os.unlink in script"),
                (r"\bshutil\.rmtree\b", "shutil.rmtree in script"),
                (r"\bsubprocess\.\w+\(.*\brm\b", "subprocess rm in script"),
                (r"\brm\s+-[rf]", "rm in script"),
            ]:
                if re.search(p, content, re.IGNORECASE):
                    print(json.dumps({"decision": "block", "reason": f"Blocked: {r}"}))
                    return
    print(json.dumps({"decision": "allow"}))

if __name__ == "__main__":
    main()
GUARDHOOK
    log "Generated guard_bash.py hook"
  fi
fi

# ─── Section 4c: Install git commit-msg hook (no co-authors) ───────────────
log "Section 4c: Installing git commit-msg guard..."
install_commit_msg_hook "$WORKSPACE_PATH" || true

# Create settings.local.json with hook config
SETTINGS_TARGET="$WORKSPACE_CLAUDE_DIR/settings.local.json"
# Get model and thinking from environment or use defaults
MODEL_SETTING="${OPENCLAW_MODEL_PRIMARY:-anthropic/claude-sonnet-4-6}"
THINKING_SETTING="${OPENCLAW_THINKING_DEFAULT:-high}"

if [[ -f "$SETTINGS_TARGET" ]] && [[ "$FORCE_OVERWRITE" == "true" ]]; then
  # Update model and thinking in existing settings without regenerating hooks
  if has python3; then
    python3 - "$SETTINGS_TARGET" "$MODEL_SETTING" "$THINKING_SETTING" <<'PYUPDATE'
import json, sys
path, model, thinking = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path, "r") as f:
    data = json.load(f)
data["model"] = model
data["thinking"] = thinking
with open(path, "w") as f:
    json.dump(data, f, indent=2, ensure_ascii=False)
    f.write("\n")
PYUPDATE
    log "Updated model=$MODEL_SETTING thinking=$THINKING_SETTING in settings.local.json"
  else
    warn "python3 not found; cannot update settings.local.json model/thinking"
  fi
elif [[ -f "$SETTINGS_TARGET" ]]; then
  skip "settings.local.json (hooks config)"
else

  cat > "$SETTINGS_TARGET" << SETTINGSJSON
{
  "model": "$model_setting",
  "thinking": "$thinking_setting",
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "python3 \"$CLAUDE_PROJECT_DIR/.claude/hooks/guard_bash.py\"",
            "timeout": 5
          }
        ]
      },
      {
        "matcher": "Write",
        "hooks": [
          {
            "type": "command",
            "command": "python3 \"$CLAUDE_PROJECT_DIR/.claude/hooks/guard_bash.py\"",
            "timeout": 5
          }
        ]
      }
    ]
  },
  "permissions": {
    "allow": [
      "Bash(git *)",
      "Bash(ls *)",
      "Bash(pwd)",
      "Bash(which *)",
      "Bash(node *)",
      "Bash(npm *)",
      "Bash(yarn *)",
      "Bash(pnpm *)",
      "Bash(npx *)",
      "Bash(make *)",
      "Bash(go *)",
      "Bash(curl *)",
      "Bash(python3 *)",
      "Read",
      "Glob",
      "Grep",
      "Write",
      "Edit"
    ],
    "deny": []
  }
}
SETTINGSJSON
  log "Created settings.local.json with guard hooks"
fi

# ─── Section 5: Create Workspace State ──────────────────────
log "Section 5: Creating workspace state..."

OPENCLAW_WS="$WORKSPACE_PATH/.openclaw"
mkdir -p "$OPENCLAW_WS"

if [[ ! -f "$OPENCLAW_WS/workspace-state.json" ]]; then
  cat > "$OPENCLAW_WS/workspace-state.json" << WSJSON
{
  "agent": "$AGENT_NAME",
  "workspace": "$WORKSPACE_PATH",
  "created": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "lastActivity": null
}
WSJSON
  log "Created workspace-state.json"
else
  skip "workspace-state.json"
fi

# ─── Section 6: Create Skills Directory ─────────────────────
if [[ "$SKIP_SKILLS" == "false" ]]; then
  log "Section 6: Creating skills directory..."
  mkdir -p "$WORKSPACE_PATH/.openclaw/skills"
  log "Skills directory ready: $WORKSPACE_PATH/.openclaw/skills/"
else
  log "Section 6: Skipping skills directory (--skip-skills)"
fi

# ─── Section 7: Convert Claude Code Skills ──────────────────
if [[ "$SKIP_SKILLS" == "false" ]]; then
  log "Section 7: Converting Claude Code skills..."

  CLAUDE_SKILLS_DIR="$WORKSPACE_PATH/.claude/skills"
  CONVERTED=0

  if [[ -d "$CLAUDE_SKILLS_DIR" ]]; then
    for skill_dir in "$CLAUDE_SKILLS_DIR"/*/; do
      [[ ! -d "$skill_dir" ]] && continue
      skill_file="$skill_dir/SKILL.md"
      [[ ! -f "$skill_file" ]] && continue

      skill_name="$(basename "$skill_dir")"

      # Skip generic/common skill patterns
      if [[ "$skill_name" =~ ^(python|rust|typescript|javascript|go|java|ruby|csharp|cpp|c)-.*$ ]]; then
        continue
      fi

      target_dir="$WORKSPACE_PATH/.openclaw/skills/$skill_name"
      target_file="$target_dir/SKILL.md"

      if [[ -f "$target_file" ]]; then
        skip ".openclaw/skills/$skill_name/SKILL.md"
        continue
      fi

      # Extract title and description from existing SKILL.md
      title_line="$(grep -m1 '^# ' "$skill_file" 2>/dev/null || echo "# $skill_name")"
      skill_title="$(echo "$title_line" | sed 's/^# //')"

      desc_line="$(grep -m1 '^> ' "$skill_file" 2>/dev/null || echo "")"
      skill_desc="$(echo "$desc_line" | sed 's/^> //')"
      [[ -z "$skill_desc" ]] && skill_desc="Skill: $skill_title"

      mkdir -p "$target_dir"

      # Write YAML frontmatter + original content
      {
        echo "---"
        echo "name: $skill_name"
        echo "description: \"$skill_desc\""
        echo "---"
        echo ""
        cat "$skill_file"
      } > "$target_file"

      log "Converted: $skill_name"
      CONVERTED=$((CONVERTED + 1))
    done
  fi

  if [[ $CONVERTED -eq 0 ]]; then
    log "No Claude Code skills found to convert"
  else
    log "Converted $CONVERTED skill(s)"
  fi

  # Copy universal pipeline skills from the installer repo.
  # These are agent-agnostic and give every OpenClaw agent autopilot quality.
  INSTALLER_SKILLS_DIR="$SCRIPT_DIR/../skills"
  UNIVERSAL_SKILLS=(autopilot-workflow quality-gates model-router session-hygiene)

  for skill_name in "${UNIVERSAL_SKILLS[@]}"; do
    src_file="$INSTALLER_SKILLS_DIR/$skill_name/SKILL.md"
    target_dir="$WORKSPACE_PATH/.openclaw/skills/$skill_name"
    target_file="$target_dir/SKILL.md"

    if [[ ! -f "$src_file" ]]; then
      continue
    fi

    if [[ -f "$target_file" ]]; then
      skip ".openclaw/skills/$skill_name/SKILL.md (already exists)"
      continue
    fi

    mkdir -p "$target_dir"
    cp "$src_file" "$target_file"
    log "Installed universal skill: $skill_name"
    CONVERTED=$((CONVERTED + 1))
  done

  # Register .openclaw/skills in OpenClaw config for discovery
  for config_path in "${CONFIG_PATHS[@]}"; do
    if [[ -f "$config_path" ]]; then
      SKILLS_DIR="$WORKSPACE_PATH/.openclaw/skills"
      python3 -c "
import json
with open('$config_path') as f:
    data = json.load(f)
skills = data.setdefault('skills', {})
load = skills.setdefault('load', {})
extra = load.setdefault('extraDirs', [])
if '$SKILLS_DIR' not in extra:
    extra.append('$SKILLS_DIR')
    with open('$config_path', 'w') as f:
        json.dump(data, f, indent=2)
" 2>/dev/null && log "Registered skills dir in $(basename "$config_path")" || true
    fi
  done
else
  log "Section 7: Skipping skill conversion (--skip-skills)"
fi

# ─── Section 7b: Create Codex Compatibility Layer ───────────
if [[ "$SKIP_CODEX" == "false" ]]; then
  log "Section 7b: Creating Codex compatibility layer..."

  CODEX_DIR="$WORKSPACE_PATH/.codex"
  AGENTS_DIR="$WORKSPACE_PATH/.agents"
  CODEX_RULES_DIR="$CODEX_DIR/rules"
  CODEX_SKILLS_LINK="$AGENTS_DIR/skills"
  ROOT_AGENTS_FILE="$WORKSPACE_PATH/AGENTS.md"
  CODEX_AGENTS_TEMPLATE="$CODEX_TEMPLATE_DIR/AGENTS.md.tmpl"
  CODEX_RULES_TEMPLATE="$CODEX_TEMPLATE_DIR/rules/default.rules.tmpl"
  CODEX_RULES_FILE="$CODEX_RULES_DIR/default.rules"

  mkdir -p "$AGENTS_DIR"
  mkdir -p "$CODEX_RULES_DIR"

  if [[ -f "$ROOT_AGENTS_FILE" ]]; then
    if grep -q "AUTO-GENERATED by add_openclaw_agent.sh (codex shim)" "$ROOT_AGENTS_FILE" 2>/dev/null; then
      skip "AGENTS.md codex shim"
    elif grep -q "^# AGENTS.md" "$ROOT_AGENTS_FILE" 2>/dev/null; then
      log "Using existing root AGENTS.md as shared OpenClaw/Codex policy"
    else
      warn "Root AGENTS.md already exists and is not managed by add_openclaw_agent.sh"
      warn "Codex will read this root AGENTS.md directly"
    fi
  else
    if [[ -f "$CODEX_AGENTS_TEMPLATE" ]]; then
      sed \
        -e "s|{{AGENT_NAME}}|$AGENT_NAME|g" \
        -e "s|{{DISPLAY_NAME}}|$DISPLAY_NAME|g" \
        -e "s|{{WORKSPACE_PATH}}|$WORKSPACE_PATH|g" \
        "$CODEX_AGENTS_TEMPLATE" > "$ROOT_AGENTS_FILE"
      log "Created AGENTS.md codex shim"
    else
      cat > "$ROOT_AGENTS_FILE" << EOF
# AGENTS.md - Codex Compatibility Shim for $DISPLAY_NAME

<!-- AUTO-GENERATED by add_openclaw_agent.sh (codex shim) -->

Read and follow \`.openclaw/AGENTS.md\` for full instructions.
This root file exists so OpenAI Codex discovers the shared policy.
EOF
      log "Created AGENTS.md codex shim (fallback)"
    fi
  fi

  # Codex loads project skills from .agents/skills.
  if [[ -L "$CODEX_SKILLS_LINK" ]]; then
    target="$(readlink "$CODEX_SKILLS_LINK" 2>/dev/null || echo "")"
    if [[ "$target" == "../.openclaw/skills" ]]; then
      skip ".agents/skills symlink"
    else
      warn ".agents/skills symlink points to unexpected target: $target"
    fi
  elif [[ -d "$CODEX_SKILLS_LINK" ]]; then
    warn ".agents/skills already exists as a directory; leaving as-is"
    warn "For full modularity, point it at ../.openclaw/skills"
  else
    ln -s "../.openclaw/skills" "$CODEX_SKILLS_LINK"
    log "Linked .agents/skills -> ../.openclaw/skills"
  fi

  if [[ -f "$CODEX_RULES_FILE" ]]; then
    skip ".codex/rules/default.rules"
  else
    if [[ -f "$CODEX_RULES_TEMPLATE" ]]; then
      sed \
        -e "s|{{AGENT_NAME}}|$AGENT_NAME|g" \
        -e "s|{{DISPLAY_NAME}}|$DISPLAY_NAME|g" \
        -e "s|{{WORKSPACE_PATH}}|$WORKSPACE_PATH|g" \
        "$CODEX_RULES_TEMPLATE" > "$CODEX_RULES_FILE"
      log "Created .codex/rules/default.rules"
    else
      cat > "$CODEX_RULES_FILE" << EOF
# AUTO-GENERATED fallback rules for $DISPLAY_NAME

prefix_rule(pattern=["rm"], decision="prompt", justification="Destructive command")
prefix_rule(pattern=["sudo"], decision="prompt", justification="Privilege escalation")
prefix_rule(pattern=["git", "push", "--force"], decision="forbidden", justification="Force push is blocked")
prefix_rule(pattern=["git", "push", "-f"], decision="forbidden", justification="Force push is blocked")
prefix_rule(pattern=["git", "push", "origin", "main"], decision="forbidden", justification="Push to main is blocked")
prefix_rule(pattern=["git", "push", "origin", "master"], decision="forbidden", justification="Push to master is blocked")
prefix_rule(pattern=["git", "commit", "--amend"], decision="forbidden", justification="Amend commits are blocked")
prefix_rule(pattern=["git", "commit", "--author"], decision="forbidden", justification="Overriding commit author is blocked")
EOF
      log "Created .codex/rules/default.rules (fallback)"
    fi
  fi
else
  log "Section 7b: Skipping Codex compatibility (--skip-codex)"
fi

# ─── Section 8: Restart Gateway ─────────────────────────────
if [[ "$NO_RESTART" == "false" ]]; then
  log "Section 8: Restarting gateway..."
  restart_out=""
  if restart_out="$(restart_openclaw_gateway)"; then
    if wait_for_gateway_ready 20; then
      log "Gateway restarted"
    else
      warn "Gateway restart completed, but gateway is still warming up"
      warn "Check status in a few seconds: openclaw gateway status"
    fi
  else
    if wait_for_gateway_ready 20; then
      warn "Gateway restart reported unhealthy during warm-up, but became healthy after retry window"
    else
      printf '%s\n' "$restart_out" >&2
      warn "Gateway restart failed (may not be running). Start with: openclaw gateway start"
    fi
  fi
else
  log "Section 8: Skipping gateway restart (--no-restart)"
fi

# ─── Section 9: Summary ─────────────────────────────────────
echo ""
echo "======================================"
echo "  $EMOJI $DISPLAY_NAME Agent Ready"
echo "======================================"
echo ""
echo "  Agent:     $AGENT_NAME"
echo "  Workspace: $WORKSPACE_PATH"
echo "  Config:    $OPENCLAW_HOME/openclaw.json"
echo "  Auth:      $AGENT_DIR/"
echo ""
echo "  Next steps:"
echo "    1. Verify: openclaw agents list"
echo "    2. Health: openclaw health"
echo "    3. Test:   openclaw agent --agent $AGENT_NAME -m \"Hello\""
echo ""
if [[ "$SKIP_PERSONA" == "false" ]]; then
  echo "  Core persona files created at repo root:"
  echo "    AGENTS.md, SOUL.md, USER.md, IDENTITY.md, TOOLS.md, HEARTBEAT.md"
  echo "    (PROJECT.md is generated by analyze_repo.sh --deep)"
  echo "  Runtime/state remains under .openclaw/ (skills, sessions, reports)"
  echo "  OpenClaw session-memory daily notes are stored at repo root: memory/YYYY-MM-DD.md"
  echo ""
fi
if [[ "$SKIP_CODEX" == "false" ]]; then
  echo "  Codex compatibility files:"
  echo "    AGENTS.md (root policy file used by both OpenClaw and Codex)"
  echo "    .agents/skills -> ../.openclaw/skills (shared skills)"
  echo "    .codex/rules/default.rules (Codex command guardrails)"
  echo ""
fi
echo "  To add skills, create SKILL.md files in:"
echo "    $WORKSPACE_PATH/.openclaw/skills/<skill-name>/SKILL.md"
echo "  (Include YAML frontmatter with 'name' and 'description')"
echo ""
