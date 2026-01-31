#!/usr/bin/env python3
import json, sys, os, datetime

data = json.load(sys.stdin)
prompt = data.get("user_prompt", "") or data.get("prompt", "")

project_dir = os.getenv("CLAUDE_PROJECT_DIR") or os.getcwd()
logs_dir = os.path.join(project_dir, ".claude", "logs")
os.makedirs(logs_dir, exist_ok=True)
with open(os.path.join(logs_dir, "prompts.log"), "a", encoding="utf-8") as f:
    f.write(f"{datetime.datetime.utcnow().isoformat()}Z\n{prompt}\n---\n")
