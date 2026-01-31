#!/usr/bin/env python3
import json, sys, datetime, os

data = json.load(sys.stdin)
cmd = data.get("tool_input", {}).get("command", "")
desc = data.get("tool_input", {}).get("description", "")

project_dir = os.getenv("CLAUDE_PROJECT_DIR") or os.getcwd()
logs_dir = os.path.join(project_dir, ".claude", "logs")
os.makedirs(logs_dir, exist_ok=True)
with open(os.path.join(logs_dir, "bash.log"), "a", encoding="utf-8") as f:
    f.write(f"{datetime.datetime.utcnow().isoformat()}Z | {cmd} | {desc}\n")
