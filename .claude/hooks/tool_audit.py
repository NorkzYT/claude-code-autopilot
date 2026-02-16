#!/usr/bin/env python3
"""
Tool audit Stop hook.

Parses the most recent transcript JSONL to extract tool usage from the latest
assistant turn, then appends a summary to .claude/logs/tool-audit.log.
"""
import json
import os
import sys
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

LOG_FILE = ".claude/logs/tool-audit.log"


def _log_error(project_dir: str, message: str):
    """Log an error to the audit log."""
    try:
        log_path = Path(project_dir) / LOG_FILE
        log_path.parent.mkdir(parents=True, exist_ok=True)
        ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        with open(log_path, "a", encoding="utf-8") as f:
            f.write(f"[{ts}] ERROR: {message}\n")
    except Exception:
        pass


def extract_latest_turn_tool_blocks(transcript_path: str) -> list[dict]:
    """
    Read JSONL transcript and return tool_use/tool_result blocks from the
    last assistant turn.
    """
    # Collect all lines, then walk backwards to find the last assistant turn
    entries = []
    with open(transcript_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entries.append(json.loads(line))
            except json.JSONDecodeError:
                continue

    # Walk backwards to find the last assistant message with tool_use content
    # We want all consecutive assistant entries at the end
    blocks = []
    found_assistant = False

    for entry in reversed(entries):
        msg = entry
        if isinstance(entry, dict) and "message" in entry:
            msg = entry["message"]
        if not isinstance(msg, dict):
            continue

        role = msg.get("role", "")
        typ = msg.get("type", "")

        is_assistant = role == "assistant" or typ in ("assistant", "assistant_message")
        is_user = role == "user" or typ in ("user", "human")
        is_result = role == "tool" or typ == "tool_result"

        if is_user and found_assistant:
            break  # We've gone past the last assistant turn

        if is_assistant or is_result:
            found_assistant = True
            content = msg.get("content", [])
            if isinstance(content, list):
                for item in content:
                    if isinstance(item, dict) and item.get("type") in ("tool_use", "tool_result"):
                        blocks.append(item)

    return blocks


def build_summary(blocks: list[dict]) -> dict:
    """
    Categorize tool blocks into:
    - tool_counts: Counter of tool names
    - files_read: list of file paths from Read calls
    - files_modified: list of (path, tool) from Edit/Write calls
    - agents_spawned: list of (subagent_type, description) from Task calls
    - errors: list of error descriptions
    """
    tool_counts = Counter()
    files_read = []
    files_modified = []
    agents_spawned = []
    errors = []

    # Index tool_use blocks by id for matching with results
    tool_use_by_id = {}

    for block in blocks:
        if block.get("type") == "tool_use":
            name = block.get("name", "unknown")
            tool_counts[name] += 1
            inp = block.get("input", {})
            block_id = block.get("id", "")
            tool_use_by_id[block_id] = block

            if name == "Read":
                fp = inp.get("file_path", "")
                if fp:
                    files_read.append(fp)
            elif name in ("Edit", "Write", "MultiEdit"):
                fp = inp.get("file_path", "")
                if fp:
                    files_modified.append((fp, name))
            elif name == "Task":
                subagent = inp.get("subagent_type", "")
                desc = inp.get("description", inp.get("prompt", ""))
                # Truncate description
                if len(desc) > 60:
                    desc = desc[:57] + "..."
                agents_spawned.append((subagent, desc))
            elif name == "Bash":
                # Store for error matching later
                pass

        elif block.get("type") == "tool_result":
            if block.get("is_error"):
                content = block.get("content", "")
                if isinstance(content, list):
                    content = " ".join(
                        c.get("text", "") for c in content if isinstance(c, dict)
                    )
                if len(content) > 80:
                    content = content[:77] + "..."
                errors.append(content)

    return {
        "tool_counts": tool_counts,
        "files_read": files_read,
        "files_modified": files_modified,
        "agents_spawned": agents_spawned,
        "errors": errors,
    }


def format_summary(summary: dict) -> str:
    """Format the summary into the log output."""
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    lines = [f"\u2550\u2550\u2550 TURN [{ts}] \u2550\u2550\u2550"]

    # Tools used
    tc = summary["tool_counts"]
    if tc:
        parts = [f"{name}({count})" for name, count in tc.most_common()]
        lines.append(f"Tools used: {', '.join(parts)}")

    # Files read
    if summary["files_read"]:
        # Shorten paths - just use basename or last 2 components
        short = [_short_path(p) for p in summary["files_read"]]
        lines.append(f"Files read: {', '.join(short)}")

    # Files modified
    if summary["files_modified"]:
        parts = [f"{_short_path(p)} ({tool})" for p, tool in summary["files_modified"]]
        lines.append(f"Files modified: {', '.join(parts)}")

    # Agents spawned
    if summary["agents_spawned"]:
        parts = [f'{st}("{desc}")' for st, desc in summary["agents_spawned"]]
        lines.append(f"Agents spawned: {', '.join(parts)}")

    # Errors
    if summary["errors"]:
        for err in summary["errors"]:
            lines.append(f"Errors: {err}")


    # Cost data from recent cost-tracker.log entry
    cost_line = _get_recent_cost_entry(os.getenv("CLAUDE_PROJECT_DIR") or os.getcwd())
    if cost_line:
        lines.append(f"Cost: {cost_line}")

    return "\n".join(lines)


def _short_path(path: str) -> str:
    """Shorten a file path to last 2-3 components."""
    parts = Path(path).parts
    if len(parts) <= 3:
        return path
    return str(Path(*parts[-3:]))


def _get_recent_cost_entry(project_dir: str) -> str:
    """Get the most recent cost-tracker.log entry, if any."""
    try:
        cost_log = Path(project_dir) / ".claude/logs/cost-tracker.log"
        if not cost_log.exists():
            return ""
        # Read last line
        with open(cost_log, "r", encoding="utf-8") as f:
            lines = f.readlines()
        if not lines:
            return ""
        last = lines[-1].strip()
        # Extract just the token counts and cost
        # Format: [timestamp] session=xxx in=N out=N cache=N cost=$N.NN
        parts = last.split("] ", 1)
        if len(parts) == 2:
            return parts[1]
        return last
    except Exception:
        return ""


def main() -> int:
    project_dir = os.getenv("CLAUDE_PROJECT_DIR") or os.getcwd()
    transcript_path = os.getenv("CLAUDE_TRANSCRIPT", "")

    if not transcript_path:
        # Try reading from stdin payload
        try:
            payload = json.load(sys.stdin)
            transcript_path = payload.get("transcript_path", "")
        except Exception:
            pass

    if not transcript_path:
        return 0  # No transcript available, skip silently

    transcript_path = os.path.expanduser(transcript_path)
    if not os.path.exists(transcript_path):
        _log_error(project_dir, f"Transcript not found: {transcript_path}")
        return 0

    try:
        blocks = extract_latest_turn_tool_blocks(transcript_path)
    except Exception as e:
        _log_error(project_dir, f"Failed to parse transcript: {e}")
        return 0

    if not blocks:
        return 0  # No tools used, skip logging

    summary = build_summary(blocks)

    # Skip if no tools were actually used
    if not summary["tool_counts"]:
        return 0

    formatted = format_summary(summary)

    try:
        log_path = Path(project_dir) / LOG_FILE
        log_path.parent.mkdir(parents=True, exist_ok=True)
        with open(log_path, "a", encoding="utf-8") as f:
            f.write(formatted + "\n\n")
    except Exception as e:
        _log_error(project_dir, f"Failed to write audit log: {e}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
