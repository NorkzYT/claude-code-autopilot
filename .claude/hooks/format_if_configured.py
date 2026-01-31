#!/usr/bin/env python3
import json, os, subprocess, sys

data = json.load(sys.stdin)
tool = data.get("tool_name", "")
inp = data.get("tool_input", {}) or {}
file_path = inp.get("file_path")  # present for Write/Edit-type tools in hooks

if not file_path or not os.path.exists(file_path):
    sys.exit(0)

def run(cmd):
    return subprocess.call(cmd, shell=True)

# JS/TS: only if prettier config exists
project_dir = os.getenv("CLAUDE_PROJECT_DIR") or os.getcwd()
if os.path.exists(os.path.join(project_dir, "package.json")) and any(os.path.exists(os.path.join(project_dir, p)) for p in [".prettierrc", ".prettierrc.json", ".prettierrc.yml", ".prettierrc.yaml"]):
    run(f'npx -y prettier --write "{file_path}" 1>/dev/null 2>/dev/null || true')

# Python: only if pyproject exists
if os.path.exists(os.path.join(project_dir, "pyproject.toml")):
    run(f'python3 -m black "{file_path}" 1>/dev/null 2>/dev/null || true')
