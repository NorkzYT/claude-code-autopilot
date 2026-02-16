#!/usr/bin/env python3
"""
OpenClaw cost tracker Stop hook.

Runs `openclaw status --usage --json` to extract token usage data,
then appends it to .claude/logs/cost-tracker.log.

Auto-detects OpenClaw via shutil.which() — graceful no-op if not found.
"""
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

LOG_FILE = ".claude/logs/cost-tracker.log"

# Alert thresholds (informational on Claude Max)
SESSION_ALERT = float(os.getenv("CLAUDE_COST_ALERT_THRESHOLD", "5.00"))
DAILY_ALERT = float(os.getenv("CLAUDE_COST_DAILY_ALERT", "20.00"))


def main() -> int:
    # Auto-detect OpenClaw
    if not shutil.which("openclaw"):
        return 0  # No-op: OpenClaw not installed

    project_dir = os.getenv("CLAUDE_PROJECT_DIR") or os.getcwd()
    session_id = os.getenv("CLAUDE_SESSION_ID", "unknown")

    # Read stdin payload (may have session metadata)
    try:
        payload = json.load(sys.stdin)
    except Exception:
        payload = {}

    # Query OpenClaw for usage stats
    try:
        result = subprocess.run(
            ["openclaw", "status", "--usage", "--json"],
            capture_output=True,
            text=True,
            timeout=10,
        )
        if result.returncode != 0:
            return 0  # OpenClaw command failed, skip silently

        usage = json.loads(result.stdout)
    except (subprocess.TimeoutExpired, json.JSONDecodeError, FileNotFoundError):
        return 0  # Skip on any error

    # Extract token data
    input_tokens = usage.get("input_tokens", 0)
    output_tokens = usage.get("output_tokens", 0)
    cache_read_tokens = usage.get("cache_read_tokens", 0)
    estimated_cost = usage.get("estimated_cost", 0.0)

    # Format log entry
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    log_entry = (
        f"[{ts}] session={session_id[:12]} "
        f"in={input_tokens} out={output_tokens} "
        f"cache={cache_read_tokens} cost=${estimated_cost:.4f}"
    )

    # Write to log
    try:
        log_path = Path(project_dir) / LOG_FILE
        log_path.parent.mkdir(parents=True, exist_ok=True)
        with open(log_path, "a", encoding="utf-8") as f:
            f.write(log_entry + "\n")
    except Exception:
        pass  # Don't fail the session for logging errors

    # Check alert thresholds (informational)
    if estimated_cost > SESSION_ALERT:
        _send_alert(
            f"Session cost alert: ${estimated_cost:.2f} "
            f"(threshold: ${SESSION_ALERT:.2f})",
            project_dir,
        )

    # Check daily total
    _check_daily_total(project_dir)

    return 0


def _check_daily_total(project_dir: str):
    """Check if daily cost exceeds threshold."""
    try:
        log_path = Path(project_dir) / LOG_FILE
        if not log_path.exists():
            return

        today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        daily_total = 0.0

        with open(log_path, "r", encoding="utf-8") as f:
            for line in f:
                if today in line and "cost=$" in line:
                    # Extract cost value
                    cost_part = line.split("cost=$")[-1].strip()
                    try:
                        daily_total += float(cost_part)
                    except ValueError:
                        continue

        if daily_total > DAILY_ALERT:
            _send_alert(
                f"Daily cost alert: ${daily_total:.2f} "
                f"(threshold: ${DAILY_ALERT:.2f})",
                project_dir,
            )
    except Exception:
        pass


def _send_alert(message: str, project_dir: str):
    """Send alert via OpenClaw notification (Discord etc)."""
    try:
        subprocess.run(
            ["openclaw", "notify", message],
            capture_output=True,
            text=True,
            timeout=5,
        )
    except Exception:
        pass  # Best-effort alerting


if __name__ == "__main__":
    raise SystemExit(main())
