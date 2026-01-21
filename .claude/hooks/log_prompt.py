#!/usr/bin/env python3
import json, sys, os, datetime

data = json.load(sys.stdin)
prompt = data.get("user_prompt", "") or data.get("prompt", "")

os.makedirs(".claude/logs", exist_ok=True)
with open(".claude/logs/prompts.log", "a", encoding="utf-8") as f:
    f.write(f"{datetime.datetime.utcnow().isoformat()}Z\n{prompt}\n---\n")
