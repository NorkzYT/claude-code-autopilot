#!/usr/bin/env python3
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path


def ensure_logs_dir(project_dir: str) -> Path:
    logs_dir = Path(project_dir) / ".claude" / "logs"
    logs_dir.mkdir(parents=True, exist_ok=True)
    return logs_dir


def main() -> int:
    # Skip notifications in remote/web environments.
    # Claude Code exposes CLAUDE_CODE_REMOTE for this purpose. :contentReference[oaicite:1]{index=1}
    if os.getenv("CLAUDE_CODE_REMOTE", "").lower() == "true":
        return 0

    project_dir = os.getenv("CLAUDE_PROJECT_DIR") or os.getcwd()
    logs_dir = ensure_logs_dir(project_dir)

    try:
        payload = json.load(sys.stdin)
    except Exception as e:
        (logs_dir / "notifications.log").write_text(
            f"{datetime.utcnow().isoformat()}Z notify_linux.py: invalid JSON: {e}\n",
            encoding="utf-8",
        )
        return 0

    notif_type = payload.get("notification_type", "")
    message = payload.get("message", "")
    cwd = payload.get("cwd", "")

    # Claude Code sends notification_type values like "permission_prompt" and "idle_prompt". :contentReference[oaicite:2]{index=2}
    if notif_type == "permission_prompt":
        title = "Claude Code: Permission required"
    elif notif_type == "idle_prompt":
        title = "Claude Code: Waiting"
    else:
        # Keep it quiet for other notification types.
        return 0

    body = message.strip()
    if cwd:
        body = f"{body}\n(cwd: {cwd})".strip()

    # Log regardless of GUI availability
    with (logs_dir / "notifications.log").open("a", encoding="utf-8") as f:
        f.write(f"{datetime.utcnow().isoformat()}Z {notif_type} {body}\n")

    # Linux desktop notification via notify-send (libnotify-bin on Debian/Ubuntu)
    notify_send = shutil.which("notify-send")
    if not notify_send:
        return 0

    try:
        subprocess.run(
            [notify_send, title, body],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        # Don’t break Claude if desktop notifications aren’t available.
        return 0

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
