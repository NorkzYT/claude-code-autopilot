#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# doctor.sh
# Validate .claude/ configuration, settings, and hooks
#
# Checks:
# - JSON syntax in settings files
# - Required fields and schema
# - Hook scripts exist and are executable
# - Hooks can actually fire (syntax check)
# - Common configuration issues
#
# Note: Invalid settings can silently disable hooks (see CCNotify docs)
# =============================================================================

ROOT="${1:-$(pwd)}"
CLAUDE_DIR="$ROOT/.claude"

# Colors (if terminal supports them)
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
  RED=$(tput setaf 1)
  GREEN=$(tput setaf 2)
  YELLOW=$(tput setaf 3)
  BLUE=$(tput setaf 4)
  RESET=$(tput sgr0)
else
  RED=""
  GREEN=""
  YELLOW=""
  BLUE=""
  RESET=""
fi

# Counters
ERRORS=0
WARNINGS=0

log_header() { printf "\n${BLUE}=== %s ===${RESET}\n" "$*"; }
log_ok() { printf "  ${GREEN}[OK]${RESET} %s\n" "$*"; }
log_warn() { printf "  ${YELLOW}[WARN]${RESET} %s\n" "$*"; WARNINGS=$((WARNINGS + 1)); }
log_err() { printf "  ${RED}[ERROR]${RESET} %s\n" "$*"; ERRORS=$((ERRORS + 1)); }
log_info() { printf "  ${BLUE}[INFO]${RESET} %s\n" "$*"; }

# -----------------------------------------------------------------------------
# Check: Directory structure
# -----------------------------------------------------------------------------
check_structure() {
  log_header "Directory Structure"

  if [[ ! -d "$CLAUDE_DIR" ]]; then
    log_err ".claude/ directory not found at $CLAUDE_DIR"
    return
  fi
  log_ok ".claude/ directory exists"

  local expected_dirs=("agents" "hooks" "logs")
  for dir in "${expected_dirs[@]}"; do
    if [[ -d "$CLAUDE_DIR/$dir" ]]; then
      log_ok "$dir/ directory exists"
    else
      log_warn "$dir/ directory missing"
    fi
  done

  # Check logs directory is writable
  if [[ -d "$CLAUDE_DIR/logs" ]]; then
    if [[ -w "$CLAUDE_DIR/logs" ]]; then
      log_ok "logs/ is writable"
    else
      log_err "logs/ is not writable (hooks cannot log)"
    fi
  fi
}

# -----------------------------------------------------------------------------
# Check: JSON settings files
# -----------------------------------------------------------------------------
check_json_syntax() {
  log_header "Settings JSON Syntax"

  local settings_files=(
    "$CLAUDE_DIR/settings.json"
    "$CLAUDE_DIR/settings.local.json"
  )

  for file in "${settings_files[@]}"; do
    if [[ -f "$file" ]]; then
      local filename
      filename="$(basename "$file")"

      # Check JSON syntax
      if command -v python3 >/dev/null 2>&1; then
        if python3 -c "import json; json.load(open('$file'))" 2>/dev/null; then
          log_ok "$filename: valid JSON"
        else
          log_err "$filename: invalid JSON syntax"
        fi
      elif command -v jq >/dev/null 2>&1; then
        if jq empty "$file" 2>/dev/null; then
          log_ok "$filename: valid JSON"
        else
          log_err "$filename: invalid JSON syntax"
        fi
      else
        log_warn "Cannot validate JSON (no python3 or jq)"
      fi
    else
      log_info "$(basename "$file"): not present (optional)"
    fi
  done
}

# -----------------------------------------------------------------------------
# Check: Settings schema (basic validation)
# -----------------------------------------------------------------------------
check_settings_schema() {
  log_header "Settings Schema"

  local settings_file="$CLAUDE_DIR/settings.local.json"
  if [[ ! -f "$settings_file" ]]; then
    settings_file="$CLAUDE_DIR/settings.json"
  fi

  if [[ ! -f "$settings_file" ]]; then
    log_warn "No settings file found"
    return
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    log_warn "python3 not available for schema validation"
    return
  fi

  python3 - "$settings_file" <<'PYTHON'
import json
import sys

file_path = sys.argv[1]
try:
    with open(file_path) as f:
        settings = json.load(f)
except Exception as e:
    print(f"  [ERROR] Cannot parse {file_path}: {e}")
    sys.exit(1)

errors = []
warnings = []

# Check hooks structure
if "hooks" in settings:
    hooks = settings["hooks"]
    valid_events = [
        "PreToolUse", "PostToolUse", "PostToolUseFailure",
        "Notification", "UserPromptSubmit", "Stop", "SubagentStop"
    ]
    for event in hooks:
        if event not in valid_events:
            warnings.append(f"Unknown hook event: {event}")

        if not isinstance(hooks[event], list):
            errors.append(f"hooks.{event} should be an array")
            continue

        for i, handler in enumerate(hooks[event]):
            if "hooks" not in handler and "matcher" not in handler:
                warnings.append(f"hooks.{event}[{i}]: missing 'hooks' or 'matcher'")

# Check permissions structure
if "permissions" in settings:
    perms = settings["permissions"]
    if "allow" in perms and not isinstance(perms["allow"], list):
        errors.append("permissions.allow should be an array")
    if "deny" in perms and not isinstance(perms["deny"], list):
        errors.append("permissions.deny should be an array")

# Output results
for e in errors:
    print(f"  \033[31m[ERROR]\033[0m {e}")
for w in warnings:
    print(f"  \033[33m[WARN]\033[0m {w}")

if not errors and not warnings:
    print("  \033[32m[OK]\033[0m Settings schema looks valid")

sys.exit(len(errors))
PYTHON

  if [[ $? -ne 0 ]]; then
    ERRORS=$((ERRORS + 1))
  fi
}

# -----------------------------------------------------------------------------
# Check: Hook scripts exist and are valid
# -----------------------------------------------------------------------------
check_hooks() {
  log_header "Hook Scripts"

  local hooks_dir="$CLAUDE_DIR/hooks"
  if [[ ! -d "$hooks_dir" ]]; then
    log_warn "hooks/ directory not found"
    return
  fi

  # Find all Python hooks
  local hook_files=()
  while IFS= read -r -d '' file; do
    hook_files+=("$file")
  done < <(find "$hooks_dir" -name "*.py" -type f -print0 2>/dev/null)

  if [[ ${#hook_files[@]} -eq 0 ]]; then
    log_warn "No hook scripts found in hooks/"
    return
  fi

  for hook in "${hook_files[@]}"; do
    local name
    name="$(basename "$hook")"

    # Check syntax
    if python3 -m py_compile "$hook" 2>/dev/null; then
      log_ok "$name: valid Python syntax"
    else
      log_err "$name: Python syntax error"
      continue
    fi

    # Check if it reads from stdin (required for hooks)
    if grep -q "sys.stdin\|json.load" "$hook" 2>/dev/null; then
      log_ok "$name: reads JSON from stdin"
    else
      log_warn "$name: may not read hook input from stdin"
    fi
  done
}

# -----------------------------------------------------------------------------
# Check: Hook references in settings
# -----------------------------------------------------------------------------
check_hook_references() {
  log_header "Hook References"

  local settings_file="$CLAUDE_DIR/settings.local.json"
  if [[ ! -f "$settings_file" ]]; then
    settings_file="$CLAUDE_DIR/settings.json"
  fi

  if [[ ! -f "$settings_file" ]]; then
    log_info "No settings file to check references"
    return
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    log_warn "python3 not available"
    return
  fi

  python3 - "$settings_file" "$CLAUDE_DIR" <<'PYTHON'
import json
import os
import re
import sys

settings_file = sys.argv[1]
claude_dir = sys.argv[2]

with open(settings_file) as f:
    settings = json.load(f)

if "hooks" not in settings:
    print("  [INFO] No hooks configured")
    sys.exit(0)

errors = 0
for event, handlers in settings["hooks"].items():
    for handler in handlers:
        hooks_list = handler.get("hooks", [])
        for hook in hooks_list:
            if hook.get("type") != "command":
                continue
            cmd = hook.get("command", "")

            # Extract script path from command
            # Handle patterns like: python3 "$CLAUDE_PROJECT_DIR/.claude/hooks/script.py"
            match = re.search(r'\.claude/hooks/(\S+\.py)', cmd)
            if match:
                script_name = match.group(1)
                script_path = os.path.join(claude_dir, "hooks", script_name)
                if os.path.exists(script_path):
                    print(f"  \033[32m[OK]\033[0m {event}: {script_name} exists")
                else:
                    print(f"  \033[31m[ERROR]\033[0m {event}: {script_name} NOT FOUND")
                    errors += 1

sys.exit(errors)
PYTHON

  if [[ $? -ne 0 ]]; then
    ERRORS=$((ERRORS + 1))
  fi
}

# -----------------------------------------------------------------------------
# Check: Agents
# -----------------------------------------------------------------------------
check_agents() {
  log_header "Agents"

  local agents_dir="$CLAUDE_DIR/agents"
  if [[ ! -d "$agents_dir" ]]; then
    log_info "agents/ directory not found"
    return
  fi

  local count=0
  while IFS= read -r -d '' file; do
    count=$((count + 1))
  done < <(find "$agents_dir" -name "*.md" -type f -print0 2>/dev/null)

  if [[ $count -eq 0 ]]; then
    log_info "No agent definitions found"
  else
    log_ok "Found $count agent definition(s)"

    # Check for YAML frontmatter
    for agent in "$agents_dir"/*.md; do
      [[ -e "$agent" ]] || continue
      local name
      name="$(basename "$agent")"
      if head -1 "$agent" | grep -q "^---"; then
        log_ok "$name: has YAML frontmatter"
      else
        log_warn "$name: missing YAML frontmatter (may not be recognized)"
      fi
    done
  fi
}

# -----------------------------------------------------------------------------
# Check: Common issues
# -----------------------------------------------------------------------------
check_common_issues() {
  log_header "Common Issues"

  # Check for $CLAUDE_PROJECT_DIR usage
  local settings_file="$CLAUDE_DIR/settings.local.json"
  if [[ -f "$settings_file" ]]; then
    if grep -q 'CLAUDE_PROJECT_DIR' "$settings_file"; then
      log_ok "Uses \$CLAUDE_PROJECT_DIR for portable paths"
    else
      log_warn "Hooks may use hardcoded paths (consider \$CLAUDE_PROJECT_DIR)"
    fi
  fi

  # Check for log file permissions
  if [[ -d "$CLAUDE_DIR/logs" ]]; then
    local perms
    perms=$(stat -c "%a" "$CLAUDE_DIR/logs" 2>/dev/null || stat -f "%Lp" "$CLAUDE_DIR/logs" 2>/dev/null || echo "unknown")
    if [[ "$perms" == "1777" || "$perms" == "777" ]]; then
      log_ok "logs/ has open permissions (multiple users can write)"
    else
      log_info "logs/ permissions: $perms (may need adjustment for multi-user)"
    fi
  fi

  # Check Python availability
  if command -v python3 >/dev/null 2>&1; then
    log_ok "python3 is available"
  else
    log_err "python3 not found (hooks will fail)"
  fi

  # Check for vendor directory
  if [[ -d "$CLAUDE_DIR/vendor" ]]; then
    log_ok "vendor/ exists (external repos installed)"
  else
    log_info "vendor/ not found (run extras/install-extras.sh to add)"
  fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
  echo ""
  echo "${BLUE}Claude Code Doctor${RESET}"
  echo "Checking: $CLAUDE_DIR"

  check_structure
  check_json_syntax
  check_settings_schema
  check_hooks
  check_hook_references
  check_agents
  check_common_issues

  log_header "Summary"
  if [[ $ERRORS -eq 0 && $WARNINGS -eq 0 ]]; then
    printf "${GREEN}All checks passed!${RESET}\n"
  else
    [[ $ERRORS -gt 0 ]] && printf "${RED}Errors: $ERRORS${RESET}\n"
    [[ $WARNINGS -gt 0 ]] && printf "${YELLOW}Warnings: $WARNINGS${RESET}\n"
  fi

  echo ""
  exit $ERRORS
}

main "$@"
