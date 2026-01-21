#!/usr/bin/env python3
import json, sys, datetime, os

data = json.load(sys.stdin)
cmd = data.get("tool_input", {}).get("command", "")
desc = data.get("tool_input", {}).get("description", "")

os.makedirs(".claude/logs", exist_ok=True)
with open(".claude/logs/bash.log", "a", encoding="utf-8") as f:
    f.write(f"{datetime.datetime.utcnow().isoformat()}Z | {cmd} | {desc}\n")
