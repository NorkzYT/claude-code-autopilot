#!/usr/bin/env python3
import json
import os
import sys
from datetime import datetime
from pathlib import Path


def ensure_logs_dir(project_dir: str) -> Path:
    logs_dir = Path(project_dir) / ".claude" / "logs"
    logs_dir.mkdir(parents=True, exist_ok=True)
    return logs_dir


def main() -> int:
    project_dir = os.getenv("CLAUDE_PROJECT_DIR") or os.getcwd()
    logs_dir = ensure_logs_dir(project_dir)

    try:
        payload = json.load(sys.stdin)
    except Exception as e:
        with (logs_dir / "tool_failures.log").open("a", encoding="utf-8") as f:
            f.write(f"{datetime.utcnow().isoformat()}Z invalid JSON: {e}\n")
        return 0

    record = {
        "ts": datetime.utcnow().isoformat() + "Z",
        "hook_event_name": payload.get("hook_event_name", "PostToolUseFailure"),
        "tool_name": payload.get("tool_name"),
        "cwd": payload.get("cwd"),
        "permission_mode": payload.get("permission_mode"),
        "payload": payload,  # keep full raw payload for deterministic triage
    }

    with (logs_dir / "tool_failures.jsonl").open("a", encoding="utf-8") as f:
        f.write(json.dumps(record, ensure_ascii=False) + "\n")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
