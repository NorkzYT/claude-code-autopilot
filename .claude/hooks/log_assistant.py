#!/usr/bin/env python3
import json
import os
import sys
import datetime
from pathlib import Path

MAX_CHARS = 20000  # keep logs readable; adjust if you want

def _extract_text(obj) -> str:
    """
    Best-effort extraction of assistant text from varying transcript schemas.
    Falls back to a compact JSON string if structure is unknown.
    """
    # Common patterns seen across transcript-like formats:
    # - { role: "assistant", content: "..." }
    # - { type: "assistant", content: [...] }
    # - { message: { role: "assistant", content: [...] } }
    candidate = obj

    if isinstance(obj, dict) and "message" in obj and isinstance(obj["message"], dict):
        candidate = obj["message"]

    role = candidate.get("role") if isinstance(candidate, dict) else None
    typ = candidate.get("type") if isinstance(candidate, dict) else None

    if role != "assistant" and typ not in ("assistant", "assistant_message"):
        # Not clearly assistant; might still contain assistant content in some schemas,
        # and we avoid mislabeling.
        return ""

    content = candidate.get("content") if isinstance(candidate, dict) else None

    # content as string
    if isinstance(content, str):
        return content.strip()

    # content as list of blocks like [{"type":"text","text":"..."}]
    if isinstance(content, list):
        parts = []
        for item in content:
            if isinstance(item, dict):
                if "text" in item and isinstance(item["text"], str):
                    parts.append(item["text"])
                elif item.get("type") == "text" and isinstance(item.get("content"), str):
                    parts.append(item["content"])
        text = "".join(parts).strip()
        if text:
            return text

    # fallback: sometimes it's under different keys
    for k in ("text", "output", "response"):
        v = candidate.get(k) if isinstance(candidate, dict) else None
        if isinstance(v, str) and v.strip():
            return v.strip()

    # last resort
    try:
        return json.dumps(candidate, ensure_ascii=False)[:MAX_CHARS]
    except Exception:
        return ""

def main():
    hook_input = json.load(sys.stdin)

    transcript_path = hook_input.get("transcript_path")
    session_id = hook_input.get("session_id", "unknown")
    event = hook_input.get("hook_event_name", "unknown")

    if not transcript_path:
        sys.exit(0)

    transcript_path = os.path.expanduser(transcript_path)
    p = Path(transcript_path)

    if not p.exists():
        sys.exit(0)

    # Read jsonl and find the last assistant message
    last_text = ""
    try:
        with p.open("r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    obj = json.loads(line)
                except Exception:
                    continue

                text = _extract_text(obj)
                if text:
                    last_text = text
    except Exception:
        sys.exit(0)

    if not last_text:
        sys.exit(0)

    if len(last_text) > MAX_CHARS:
        last_text = last_text[:MAX_CHARS] + "\n...[truncated]..."

    os.makedirs(".claude/logs", exist_ok=True)
    out_path = Path(".claude/logs/assistant_output.log")

    ts = datetime.datetime.utcnow().isoformat() + "Z"
    with out_path.open("a", encoding="utf-8") as f:
        f.write(f"{ts} | session={session_id} | event={event}\n")
        f.write(last_text)
        f.write("\n\n---\n\n")

if __name__ == "__main__":
    main()
