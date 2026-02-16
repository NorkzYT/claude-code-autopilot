#!/usr/bin/env python3
"""
OpenClaw memory sync Stop hook.

Syncs session state from .claude/context/<task>/ to OpenClaw's memory directory
for RAG indexing. Also syncs the latest tool-audit.log entry.

Auto-detects OpenClaw via shutil.which() -- graceful no-op if not found.
"""
import json
import os
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path


def main() -> int:
    # Auto-detect OpenClaw
    if not shutil.which("openclaw"):
        return 0  # No-op: OpenClaw not installed

    project_dir = os.getenv("CLAUDE_PROJECT_DIR") or os.getcwd()
    session_id = os.getenv("CLAUDE_SESSION_ID", "default")
    task_name = os.getenv(
        "CLAUDE_TASK_NAME",
        session_id[:8] if session_id != "default" else "current",
    )

    # Read stdin payload
    try:
        payload = json.load(sys.stdin)
    except Exception:
        payload = {}

    # Find OpenClaw workspace memory directory
    openclaw_home = os.getenv("OPENCLAW_HOME", os.path.expanduser("~/.openclaw"))
    memory_dir = Path(openclaw_home) / "memory" / "claude-sessions" / task_name

    # Source: .claude/context/<task>/
    context_dir = Path(project_dir) / ".claude" / "context" / task_name

    if not context_dir.exists():
        return 0  # No session state to sync

    # Create memory destination
    try:
        memory_dir.mkdir(parents=True, exist_ok=True)
    except Exception:
        return 0  # Can't create directory, skip

    # Sync three-file pattern
    for filename in ("plan.md", "context.md", "tasks.md"):
        src = context_dir / filename
        dst = memory_dir / filename
        if src.exists():
            try:
                shutil.copy2(str(src), str(dst))
            except Exception:
                continue

    # Sync latest tool-audit.log entry
    _sync_audit_entry(project_dir, memory_dir)

    # Write sync metadata
    try:
        meta = {
            "synced_at": datetime.now(timezone.utc).isoformat(),
            "session_id": session_id,
            "task_name": task_name,
            "project_dir": project_dir,
        }
        meta_path = memory_dir / "sync-metadata.json"
        with open(meta_path, "w", encoding="utf-8") as f:
            json.dump(meta, f, indent=2)
    except Exception:
        pass

    return 0


def _sync_audit_entry(project_dir: str, memory_dir: Path):
    """Copy the latest tool-audit.log entry to memory for searchable audit trail."""
    try:
        audit_log = Path(project_dir) / ".claude" / "logs" / "tool-audit.log"
        if not audit_log.exists():
            return

        # Read last entry (entries are separated by blank lines)
        content = audit_log.read_text(encoding="utf-8")
        entries = content.strip().split("\n\n")
        if not entries:
            return

        last_entry = entries[-1].strip()
        if not last_entry:
            return

        # Append to memory audit trail
        audit_dest = memory_dir / "audit-trail.log"
        with open(audit_dest, "a", encoding="utf-8") as f:
            f.write(last_entry + "\n\n")
    except Exception:
        pass


if __name__ == "__main__":
    raise SystemExit(main())
