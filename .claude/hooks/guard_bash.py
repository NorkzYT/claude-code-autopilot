#!/usr/bin/env python3
"""
Guard hook to block dangerous bash commands.
Matches deny patterns from .claude/settings.local.json
"""
import json, sys, re

data = json.load(sys.stdin)
cmd = (data.get("tool_input", {}) or {}).get("command", "") or ""

# Blocked command patterns matching settings.local.json deny list
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

    # Windows shells
    (r"\bpowershell\b", "powershell"),
    (r"\bcmd\.exe\b", "cmd.exe"),

    # Additional dangerous patterns
    (r"\bmkfs\b", "mkfs"),
    (r":\(\)\s*\{\s*:\s*\|\s*:\s*;\s*\}\s*;\s*:", "fork bomb"),
    (r"\bcurl\b.*\|\s*(sh|bash)\b", "curl pipe to shell"),
    (r"\bwget\b.*\|\s*(sh|bash)\b", "wget pipe to shell"),
]

for pattern, name in blocked:
    if re.search(pattern, cmd, re.IGNORECASE):
        print(f"BLOCKED: '{name}' command not allowed. Pattern: {pattern}", file=sys.stderr)
        sys.exit(2)

sys.exit(0)
