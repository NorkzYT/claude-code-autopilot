#!/usr/bin/env python3
"""
Cross-platform notification hook for Claude Code.

Supports multiple notification backends (configure via environment variables):

1. ntfy.sh (free, recommended for remote dev):
   export CLAUDE_NTFY_TOPIC="your-unique-topic-name"
   # Then subscribe at https://ntfy.sh/your-unique-topic-name or install the app

2. Pushover (paid, reliable):
   export CLAUDE_PUSHOVER_USER="your-user-key"
   export CLAUDE_PUSHOVER_TOKEN="your-app-token"

3. Discord webhook:
   export CLAUDE_DISCORD_WEBHOOK="https://discord.com/api/webhooks/..."

4. Slack webhook:
   export CLAUDE_SLACK_WEBHOOK="https://hooks.slack.com/services/..."

5. Linux desktop (fallback, requires notify-send):
   No config needed, auto-detected.

Set CLAUDE_NOTIFY_DISABLE=1 to disable all notifications.
"""
import json
import os
import shutil
import subprocess
import sys
import urllib.request
import urllib.error
from datetime import datetime
from pathlib import Path


def ensure_logs_dir(project_dir: str) -> Path:
    logs_dir = Path(project_dir) / ".claude" / "logs"
    logs_dir.mkdir(parents=True, exist_ok=True)
    return logs_dir


def send_ntfy(topic: str, title: str, body: str, logs_dir: Path = None) -> bool:
    """Send notification via ntfy.sh"""
    try:
        url = f"https://ntfy.sh/{topic}"
        data = body.encode("utf-8")
        req = urllib.request.Request(
            url,
            data=data,
            headers={
                "Title": title,
                "Priority": "high" if "Permission" in title else "default",
                "Tags": "robot",
            },
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=5) as resp:
            return resp.status == 200
    except Exception as e:
        if logs_dir:
            with (logs_dir / "notifications.log").open("a", encoding="utf-8") as f:
                f.write(f"{datetime.utcnow().isoformat()}Z ntfy error: {e}\n")
        return False


def send_pushover(user: str, token: str, title: str, body: str, logs_dir: Path = None) -> bool:
    """Send notification via Pushover"""
    try:
        data = urllib.parse.urlencode({
            "token": token,
            "user": user,
            "title": title,
            "message": body,
            "priority": 1 if "Permission" in title else 0,
        }).encode("utf-8")
        req = urllib.request.Request(
            "https://api.pushover.net/1/messages.json",
            data=data,
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=5) as resp:
            return resp.status == 200
    except Exception as e:
        if logs_dir:
            with (logs_dir / "notifications.log").open("a", encoding="utf-8") as f:
                f.write(f"{datetime.utcnow().isoformat()}Z pushover error: {e}\n")
        return False


def send_discord(webhook_url: str, title: str, body: str, logs_dir: Path = None) -> bool:
    """Send notification via Discord webhook"""
    try:
        payload = json.dumps({
            "embeds": [{
                "title": title,
                "description": body,
                "color": 0xFF6600 if "Permission" in title else 0x00FF00,
            }]
        }).encode("utf-8")
        req = urllib.request.Request(
            webhook_url,
            data=payload,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=5) as resp:
            return resp.status in (200, 204)
    except Exception as e:
        if logs_dir:
            with (logs_dir / "notifications.log").open("a", encoding="utf-8") as f:
                f.write(f"{datetime.utcnow().isoformat()}Z discord error: {e}\n")
        return False


def send_slack(webhook_url: str, title: str, body: str, logs_dir: Path = None) -> bool:
    """Send notification via Slack webhook"""
    try:
        payload = json.dumps({
            "text": f"*{title}*\n{body}",
        }).encode("utf-8")
        req = urllib.request.Request(
            webhook_url,
            data=payload,
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=5) as resp:
            return resp.status == 200
    except Exception as e:
        if logs_dir:
            with (logs_dir / "notifications.log").open("a", encoding="utf-8") as f:
                f.write(f"{datetime.utcnow().isoformat()}Z slack error: {e}\n")
        return False


def send_notify_send(title: str, body: str, logs_dir: Path = None) -> bool:
    """Send notification via Linux notify-send"""
    notify_send = shutil.which("notify-send")
    if not notify_send:
        if logs_dir:
            with (logs_dir / "notifications.log").open("a", encoding="utf-8") as f:
                f.write(f"{datetime.utcnow().isoformat()}Z notify-send: not found\n")
        return False
    try:
        result = subprocess.run(
            [notify_send, title, body],
            check=False,
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            if logs_dir:
                with (logs_dir / "notifications.log").open("a", encoding="utf-8") as f:
                    f.write(f"{datetime.utcnow().isoformat()}Z notify-send failed: {result.stderr.strip()}\n")
            return False
        return True
    except Exception as e:
        if logs_dir:
            with (logs_dir / "notifications.log").open("a", encoding="utf-8") as f:
                f.write(f"{datetime.utcnow().isoformat()}Z notify-send error: {e}\n")
        return False


def main() -> int:
    # Disable all notifications if requested
    if os.getenv("CLAUDE_NOTIFY_DISABLE", "").lower() in ("1", "true"):
        return 0

    project_dir = os.getenv("CLAUDE_PROJECT_DIR") or os.getcwd()
    logs_dir = ensure_logs_dir(project_dir)

    try:
        payload = json.load(sys.stdin)
    except Exception as e:
        with (logs_dir / "notifications.log").open("a", encoding="utf-8") as f:
            f.write(f"{datetime.utcnow().isoformat()}Z notify: invalid JSON: {e}\n")
        return 0

    notif_type = payload.get("notification_type", "")
    message = payload.get("message", "")
    cwd = payload.get("cwd", "")

    # Only notify for important events
    if notif_type == "permission_prompt":
        title = "Claude Code: Permission required"
    elif notif_type == "idle_prompt":
        title = "Claude Code: Waiting for input"
    else:
        return 0

    body = message.strip()
    if cwd:
        # Shorten path for readability
        short_cwd = cwd.replace(os.path.expanduser("~"), "~")
        body = f"{body}\n({short_cwd})"

    # Log regardless of notification success
    with (logs_dir / "notifications.log").open("a", encoding="utf-8") as f:
        f.write(f"{datetime.utcnow().isoformat()}Z [{notif_type}] {body}\n")

    # Try notification backends in order of preference
    sent = False
    backends_tried = []

    # 1. ntfy.sh (best for remote dev)
    # Check env var first, then config file
    ntfy_topic = os.getenv("CLAUDE_NTFY_TOPIC")
    if not ntfy_topic:
        ntfy_config = Path.home() / ".config" / "claude-code" / "ntfy_topic"
        if ntfy_config.exists():
            ntfy_topic = ntfy_config.read_text().strip()
    if ntfy_topic and not sent:
        backends_tried.append("ntfy")
        sent = send_ntfy(ntfy_topic, title, body, logs_dir)

    # 2. Pushover
    pushover_user = os.getenv("CLAUDE_PUSHOVER_USER")
    pushover_token = os.getenv("CLAUDE_PUSHOVER_TOKEN")
    if pushover_user and pushover_token and not sent:
        backends_tried.append("pushover")
        sent = send_pushover(pushover_user, pushover_token, title, body, logs_dir)

    # 3. Discord webhook
    discord_webhook = os.getenv("CLAUDE_DISCORD_WEBHOOK")
    if discord_webhook and not sent:
        backends_tried.append("discord")
        sent = send_discord(discord_webhook, title, body, logs_dir)

    # 4. Slack webhook
    slack_webhook = os.getenv("CLAUDE_SLACK_WEBHOOK")
    if slack_webhook and not sent:
        backends_tried.append("slack")
        sent = send_slack(slack_webhook, title, body, logs_dir)

    # 5. Linux desktop (fallback)
    is_remote = os.getenv("CLAUDE_CODE_REMOTE", "").lower() == "true"
    if not sent and not is_remote:
        backends_tried.append("notify-send")
        sent = send_notify_send(title, body, logs_dir)

    # Log warning if no notification was sent
    if not sent:
        with (logs_dir / "notifications.log").open("a", encoding="utf-8") as f:
            if not backends_tried:
                f.write(f"{datetime.utcnow().isoformat()}Z WARNING: No notification backend configured. "
                        "Set CLAUDE_NTFY_TOPIC or run: bash .claude/bootstrap/linux_devtools.sh\n")
            else:
                f.write(f"{datetime.utcnow().isoformat()}Z WARNING: Notification failed via: {', '.join(backends_tried)}\n")

    return 0


if __name__ == "__main__":
    # Import urllib.parse here to avoid issues if not needed
    import urllib.parse
    raise SystemExit(main())
