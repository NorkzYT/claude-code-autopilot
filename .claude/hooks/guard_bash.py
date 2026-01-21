#!/usr/bin/env python3
import json, sys, re

data = json.load(sys.stdin)
cmd = (data.get("tool_input", {}) or {}).get("command", "") or ""

blocked = [
    r"\brm\s+-rf\b",
    r"\bmkfs\b",
    r":\(\)\s*\{\s*:\s*\|\s*:\s*;\s*\}\s*;\s*:",  # fork bomb
    r"\bcurl\b.*\|\s*(sh|bash)\b",
    r"\bwget\b.*\|\s*(sh|bash)\b"
]

for pat in blocked:
    if re.search(pat, cmd):
        print(f"Blocked dangerous command pattern: {pat}", file=sys.stderr)
        sys.exit(2)

sys.exit(0)
