#!/usr/bin/env python3
"""
Ralph Wiggum iterative loop hook.

This Stop hook implements iterative, self-referential AI development loops.
When active, it blocks session exit and feeds the same prompt back to continue
working until a completion promise is fulfilled.

State file format (.claude/ralph-loop.local.md):
---
active: true
iteration: 1
max_iterations: 20
completion_promise: "DONE"
started_at: "2024-01-01T00:00:00Z"
---

Your task prompt here

The hook reads the transcript to find Claude's last output and checks for
<promise>TEXT</promise> tags that match the completion_promise.
"""
import json
import os
import re
import sys
from datetime import datetime
from pathlib import Path
from typing import Optional

# State file location
STATE_FILE = ".claude/ralph-loop.local.md"


def parse_state_file(content: str) -> tuple[dict, str]:
    """
    Parse YAML frontmatter and body from state file.
    Returns (frontmatter_dict, body_text).
    """
    frontmatter = {}
    body = content

    # Check for YAML frontmatter
    if content.startswith("---"):
        parts = content.split("---", 2)
        if len(parts) >= 3:
            yaml_content = parts[1].strip()
            body = parts[2].strip()

            # Simple YAML parsing (key: value pairs)
            for line in yaml_content.split("\n"):
                line = line.strip()
                if ":" in line:
                    key, value = line.split(":", 1)
                    key = key.strip()
                    value = value.strip().strip('"').strip("'")

                    # Type conversion
                    if value.lower() == "true":
                        value = True
                    elif value.lower() == "false":
                        value = False
                    elif value.isdigit():
                        value = int(value)

                    frontmatter[key] = value

    return frontmatter, body


def write_state_file(path: Path, frontmatter: dict, body: str):
    """Write state file with updated frontmatter."""
    yaml_lines = ["---"]
    for key, value in frontmatter.items():
        if isinstance(value, bool):
            yaml_lines.append(f"{key}: {str(value).lower()}")
        elif isinstance(value, str):
            yaml_lines.append(f'{key}: "{value}"')
        else:
            yaml_lines.append(f"{key}: {value}")
    yaml_lines.append("---")
    yaml_lines.append("")
    yaml_lines.append(body)

    path.write_text("\n".join(yaml_lines))


def extract_last_assistant_text(transcript_path: str) -> str:
    """Extract the last assistant message from the JSONL transcript."""
    last_text = ""

    try:
        with open(transcript_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except json.JSONDecodeError:
                    continue

                # Handle various transcript formats
                candidate = obj
                if isinstance(obj, dict) and "message" in obj:
                    candidate = obj["message"]

                if not isinstance(candidate, dict):
                    continue

                role = candidate.get("role", "")
                typ = candidate.get("type", "")

                if role != "assistant" and typ not in ("assistant", "assistant_message"):
                    continue

                content = candidate.get("content", "")

                if isinstance(content, str):
                    last_text = content
                elif isinstance(content, list):
                    parts = []
                    for item in content:
                        if isinstance(item, dict):
                            if "text" in item:
                                parts.append(item["text"])
                            elif item.get("type") == "text" and "content" in item:
                                parts.append(item["content"])
                    if parts:
                        last_text = "".join(parts)

    except Exception:
        pass

    return last_text


def check_completion_promise(text: str, promise: str) -> bool:
    """
    Check if the text contains the completion promise.
    Looks for <promise>TEXT</promise> tags.
    """
    # Check for promise tags
    promise_pattern = r"<promise>(.*?)</promise>"
    matches = re.findall(promise_pattern, text, re.IGNORECASE | re.DOTALL)

    for match in matches:
        if match.strip().upper() == promise.upper():
            return True

    # Also check for bare promise text as fallback
    if promise.upper() in text.upper():
        return True

    return False


def is_idle_response(text: str) -> bool:
    """
    Detect if a response indicates the agent is idle/waiting for input.
    These patterns indicate the task is done but agent didn't output completion promise.
    """
    text = text.strip()

    # Very short responses (under 50 chars) that are just waiting
    idle_patterns = [
        r"^\.*$",  # Just dots
        r"^standing by\.?$",
        r"^ready\.?$",
        r"^ready when you are\.?$",
        r"^awaiting.*input\.?$",
        r"^listening\.?$",
        r"^waiting\.?$",
    ]

    for pattern in idle_patterns:
        if re.match(pattern, text, re.IGNORECASE):
            return True

    # Very short responses (under 20 chars) are likely idle
    if len(text) < 20 and not text.startswith("<"):
        return True

    return False


def main() -> int:
    # Read hook input
    try:
        payload = json.load(sys.stdin)
    except Exception:
        payload = {}

    project_dir = os.getenv("CLAUDE_PROJECT_DIR") or os.getcwd()
    state_path = Path(project_dir) / STATE_FILE

    # Check if state file exists
    if not state_path.exists():
        return 0  # No loop active, allow exit

    try:
        content = state_path.read_text()
        frontmatter, body = parse_state_file(content)
    except Exception as e:
        print(f"Error reading ralph-loop state: {e}", file=sys.stderr)
        return 0

    # Check if loop is active
    if not frontmatter.get("active", False):
        return 0  # Loop not active, allow exit

    iteration = frontmatter.get("iteration", 1)
    max_iterations = frontmatter.get("max_iterations", 20)
    completion_promise = frontmatter.get("completion_promise", "DONE")

    # Check iteration limit
    if iteration >= max_iterations:
        print(f"Ralph loop reached max iterations ({max_iterations}). Deactivating.", file=sys.stderr)
        frontmatter["active"] = False
        frontmatter["ended_at"] = datetime.utcnow().isoformat() + "Z"
        frontmatter["end_reason"] = "max_iterations"
        write_state_file(state_path, frontmatter, body)
        return 0  # Allow exit

    # Get transcript path from hook input
    transcript_path = payload.get("transcript_path")
    consecutive_idle = frontmatter.get("consecutive_idle", 0)
    max_idle = 3  # Auto-exit after 3 consecutive idle responses

    if transcript_path:
        transcript_path = os.path.expanduser(transcript_path)
        last_output = extract_last_assistant_text(transcript_path)

        # Check for completion promise
        if check_completion_promise(last_output, completion_promise):
            print(f"Ralph loop completed: Promise '{completion_promise}' fulfilled.", file=sys.stderr)
            frontmatter["active"] = False
            frontmatter["ended_at"] = datetime.utcnow().isoformat() + "Z"
            frontmatter["end_reason"] = "promise_fulfilled"
            write_state_file(state_path, frontmatter, body)
            return 0  # Allow exit

        # Check for idle/waiting responses
        if is_idle_response(last_output):
            consecutive_idle += 1
            frontmatter["consecutive_idle"] = consecutive_idle

            if consecutive_idle >= max_idle:
                print(f"Ralph loop detected idle agent ({consecutive_idle} consecutive). Auto-exiting.", file=sys.stderr)
                frontmatter["active"] = False
                frontmatter["ended_at"] = datetime.utcnow().isoformat() + "Z"
                frontmatter["end_reason"] = "idle_detected"
                write_state_file(state_path, frontmatter, body)
                return 0  # Allow exit
        else:
            # Reset idle counter on substantive response
            frontmatter["consecutive_idle"] = 0

    # Loop continues - increment iteration and block exit
    frontmatter["iteration"] = iteration + 1
    frontmatter["last_run_at"] = datetime.utcnow().isoformat() + "Z"
    write_state_file(state_path, frontmatter, body)

    # Output the prompt to continue the loop
    # Use stdout for status (not stderr which shows as "error" in CLI)
    # Return the prompt as JSON to inject into next iteration
    output = {
        "decision": "block",
        "reason": f"Ralph loop continuing ({iteration + 1}/{max_iterations})",
        "outputToUser": f"🔄 Ralph Loop: Iteration {iteration + 1}/{max_iterations}",
        "prompt": body
    }
    print(json.dumps(output))

    # Exit code 2 blocks the stop
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
