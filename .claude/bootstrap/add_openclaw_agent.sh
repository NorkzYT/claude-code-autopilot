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
#   --skip-persona            Don't create persona files
#   --skip-skills             Don't create skills/ directory
#   --no-restart              Don't restart the gateway
#
# Example:
#   bash .claude/bootstrap/add_openclaw_agent.sh kairo /opt/github/Kairo --name "Kairo" --emoji "🔧"
# ─────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$(cd "$SCRIPT_DIR/../templates/agent-persona" && pwd 2>/dev/null || echo "")"
OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"

# ─── Defaults ───────────────────────────────────────────────
DISPLAY_NAME=""
EMOJI="🔧"
SKIP_PERSONA=false
SKIP_SKILLS=false
NO_RESTART=false

# ─── Helpers ────────────────────────────────────────────────
log()  { echo "  [+] $*"; }
warn() { echo "  [!] $*" >&2; }
err()  { echo "  [ERROR] $*" >&2; exit 1; }
skip() { echo "  [~] $* (already exists, skipping)"; }

usage() {
  echo "Usage: bash $0 <agent-name> <workspace-path> [options]"
  echo ""
  echo "Options:"
  echo "  --name <display-name>     Display name (default: capitalized agent-name)"
  echo "  --emoji <emoji>           Agent emoji (default: 🔧)"
  echo "  --skip-persona            Don't create persona files"
  echo "  --skip-skills             Don't create skills/ directory"
  echo "  --no-restart              Don't restart the gateway"
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
    --no-restart)   NO_RESTART=true; shift ;;
    -h|--help)    usage ;;
    *)            err "Unknown option: $1" ;;
  esac
done

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
  if openclaw agents add "$AGENT_NAME" --workspace "$WORKSPACE_PATH" 2>/dev/null; then
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

# Both config paths need the agent entry
CONFIG_PATHS=(
  "$OPENCLAW_HOME/openclaw.json"
  "$OPENCLAW_HOME/.openclaw/openclaw.json"
)

for config_path in "${CONFIG_PATHS[@]}"; do
  if [[ ! -f "$config_path" ]]; then
    mkdir -p "$(dirname "$config_path")"
    echo '{"agents":[]}' > "$config_path"
    log "Created config: $config_path"
  fi

  # Check if agent already in config
  if python3 -c "
import json, sys
with open('$config_path') as f:
    data = json.load(f)
agents = data.get('agents', [])
names = [a.get('name', '') for a in agents]
sys.exit(0 if '$AGENT_NAME' in names else 1)
" 2>/dev/null; then
    skip "Agent already in $(basename "$(dirname "$config_path")")/$(basename "$config_path")"
  else
    python3 -c "
import json
config_path = '$config_path'
with open(config_path) as f:
    data = json.load(f)
if 'agents' not in data:
    data['agents'] = []
data['agents'].append({
    'name': '$AGENT_NAME',
    'displayName': '$DISPLAY_NAME',
    'workspace': '$WORKSPACE_PATH',
    'emoji': '$EMOJI'
})
with open(config_path, 'w') as f:
    json.dump(data, f, indent=2)
" 2>/dev/null && log "Added agent to $(basename "$(dirname "$config_path")")/$(basename "$config_path")" \
              || warn "Failed to update $config_path"
  fi
done

# ─── Section 4: Create Persona Files ────────────────────────
if [[ "$SKIP_PERSONA" == "false" ]]; then
  log "Section 4: Creating persona files..."

  # Ensure .openclaw directory exists
  mkdir -p "$WORKSPACE_PATH/.openclaw"

  for tmpl in "$TEMPLATE_DIR"/*.tmpl; do
    [[ ! -f "$tmpl" ]] && continue
    filename="$(basename "$tmpl" .tmpl)"
    target="$WORKSPACE_PATH/.openclaw/$filename"

    if [[ -f "$target" ]]; then
      skip "$filename"
      continue
    fi

    sed \
      -e "s|{{AGENT_NAME}}|$AGENT_NAME|g" \
      -e "s|{{DISPLAY_NAME}}|$DISPLAY_NAME|g" \
      -e "s|{{WORKSPACE_PATH}}|$WORKSPACE_PATH|g" \
      -e "s|{{EMOJI}}|$EMOJI|g" \
      "$tmpl" > "$target"
    log "Created .openclaw/$filename"
  done

  # Clean up any persona files that were mistakenly created at repo root
  PERSONA_FILES="AGENTS.md SOUL.md USER.md IDENTITY.md TOOLS.md HEARTBEAT.md BOOTSTRAP.md MEMORY.md"
  for pfile in $PERSONA_FILES; do
    root_file="$WORKSPACE_PATH/$pfile"
    openclaw_file="$WORKSPACE_PATH/.openclaw/$pfile"
    if [[ -f "$root_file" ]] && [[ -f "$openclaw_file" ]]; then
      rm -f "$root_file"
      log "Cleaned up root-level duplicate: $pfile (kept .openclaw/$pfile)"
    elif [[ -f "$root_file" ]] && [[ ! -f "$openclaw_file" ]]; then
      mv "$root_file" "$openclaw_file"
      log "Moved root-level $pfile to .openclaw/$pfile"
    fi
  done
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

# Create settings.local.json with hook config
SETTINGS_TARGET="$WORKSPACE_CLAUDE_DIR/settings.local.json"
if [[ -f "$SETTINGS_TARGET" ]]; then
  skip "settings.local.json (hooks config)"
else
  cat > "$SETTINGS_TARGET" << 'SETTINGSJSON'
{
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

# ─── Section 8: Restart Gateway ─────────────────────────────
if [[ "$NO_RESTART" == "false" ]]; then
  log "Section 8: Restarting gateway..."
  if openclaw gateway restart 2>/dev/null; then
    log "Gateway restarted"
  else
    warn "Gateway restart failed (may not be running). Start with: openclaw gateway start"
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
  echo "  Persona files created in .openclaw/:"
  echo "    .openclaw/AGENTS.md, SOUL.md, USER.md, IDENTITY.md, TOOLS.md, HEARTBEAT.md"
  echo ""
fi
echo "  To add skills, create SKILL.md files in:"
echo "    $WORKSPACE_PATH/.openclaw/skills/<skill-name>/SKILL.md"
echo "  (Include YAML frontmatter with 'name' and 'description')"
echo ""
