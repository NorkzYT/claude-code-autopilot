#!/usr/bin/env python3
"""
Guard hook to block dangerous bash commands.
Matches deny patterns from .claude/settings.local.json

Supply-chain security: blocks npx, curl|bash, and other remote code execution
patterns that are common attack vectors in agent workflows.
See: https://www.aikido.dev/blog/agent-skills-spreading-hallucinated-npx-commands
"""
import json
import os
import re
import sys

data = json.load(sys.stdin)
cmd = (data.get("tool_input", {}) or {}).get("command", "") or ""

# -----------------------------------------------------------------------------
# Allowlist: explicitly permitted npx/pip/npm commands
# Add packages here that you trust and want to allow
# -----------------------------------------------------------------------------
ALLOWLISTED_NPX = [
    # Example: r"^npx\s+prettier\b",
    # Example: r"^npx\s+eslint\b",
]

ALLOWLISTED_PIP = [
    # Example: r"^pip\s+install\s+pytest\b",
]

ALLOWLISTED_NPM = [
    # Example: r"^npm\s+install\s+--save-dev\s+typescript\b",
]

def is_allowlisted(cmd: str, allowlist: list) -> bool:
    """Check if command matches any allowlist pattern."""
    for pattern in allowlist:
        if re.search(pattern, cmd, re.IGNORECASE):
            return True
    return False

# -----------------------------------------------------------------------------
# Blocked patterns
# -----------------------------------------------------------------------------
blocked = [
    # Destructive file operations
    (r"\brm\s+-rf\b", "rm -rf"),
    (r"\brm\s+-r\b", "rm -r"),
    (r"^\s*rm\s+", "rm"),
    (r"\bdel\b", "del"),
    (r"\brmdir\b", "rmdir"),

    # Privilege escalation
    (r"^\s*sudo\s+", "sudo"),
    (r"^\s*doas\s+", "doas"),

    # Network/remote commands (potential data exfiltration)
    (r"^\s*curl\s+", "curl"),
    (r"^\s*wget\s+", "wget"),
    (r"^\s*ssh\s+", "ssh"),
    (r"^\s*scp\s+", "scp"),
    (r"^\s*rsync\s+", "rsync"),

    # Git commit (prevent auto-commits)
    (r"\bgit\s+commit\b", "git commit"),

    # Git staging (prevent auto-staging - files should not be staged automatically)
    (r"\bgit\s+add\b", "git add"),
    (r"\bgit\s+stage\b", "git stage"),

    # Windows shells
    (r"\bpowershell\b", "powershell"),
    (r"\bcmd\.exe\b", "cmd.exe"),

    # Additional dangerous patterns
    (r"\bmkfs\b", "mkfs"),
    (r":\(\)\s*\{\s*:\s*\|\s*:\s*;\s*\}\s*;\s*:", "fork bomb"),

    # Remote code execution patterns (supply-chain attacks)
    (r"\bcurl\b.*\|\s*(sh|bash|zsh|python|python3|perl|ruby)\b", "curl pipe to interpreter"),
    (r"\bwget\b.*\|\s*(sh|bash|zsh|python|python3|perl|ruby)\b", "wget pipe to interpreter"),
    (r"\bcurl\b.*>\s*[^|]+\s*&&\s*(sh|bash|chmod\s+\+x)", "curl download and execute"),
    (r"\bwget\b.*&&\s*(sh|bash|chmod\s+\+x)", "wget download and execute"),

    # Base64 decoding to shell (obfuscation technique)
    (r"base64\s+-d.*\|\s*(sh|bash)", "base64 decode to shell"),
    (r"echo\s+.*\|\s*base64\s+-d\s*\|\s*(sh|bash)", "echo base64 to shell"),
]

# Supply-chain: npx commands (hallucinated package attacks)
# Block by default unless explicitly allowlisted
blocked_supply_chain = [
    (r"^\s*npx\s+", "npx (supply-chain risk)", ALLOWLISTED_NPX),
    (r"\|\s*npx\s+", "pipe to npx (supply-chain risk)", ALLOWLISTED_NPX),

    # npm install with unknown packages (can execute postinstall scripts)
    (r"^\s*npm\s+install\s+(?!--save-dev\s+@types/)", "npm install (postinstall risk)", ALLOWLISTED_NPM),
    (r"^\s*npm\s+i\s+", "npm i (postinstall risk)", ALLOWLISTED_NPM),

    # pip install from URLs or git repos (arbitrary code execution)
    (r"^\s*pip\s+install\s+(https?://|git\+)", "pip install from URL/git", ALLOWLISTED_PIP),
    (r"^\s*pip3?\s+install\s+(https?://|git\+)", "pip install from URL/git", ALLOWLISTED_PIP),

    # pip install without version pinning (can pull malicious versions)
    (r"^\s*pip3?\s+install\s+(?!-r\s+requirements)(?!-e\s+\.)(?!--upgrade\s+pip)", "pip install (unvetted)", ALLOWLISTED_PIP),
]

# Check standard blocked patterns
for pattern, name in blocked:
    if re.search(pattern, cmd, re.IGNORECASE):
        print(f"BLOCKED: '{name}' command not allowed. Pattern: {pattern}", file=sys.stderr)
        sys.exit(2)

# Check supply-chain patterns (with allowlist support)
for pattern, name, allowlist in blocked_supply_chain:
    if re.search(pattern, cmd, re.IGNORECASE):
        if not is_allowlisted(cmd, allowlist):
            print(f"BLOCKED: '{name}' - add to allowlist in guard_bash.py if trusted", file=sys.stderr)
            sys.exit(2)

sys.exit(0)
