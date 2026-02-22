#!/usr/bin/env python3
"""
Inject cost-optimized execution routing guidance on substantive prompts.

This preserves quality while reducing usage:
- Plan/triage first on the current model (typically Sonnet)
- Work directly for small tasks
- Escalate to autopilot-opus only for complex multi-file changes
"""
import json
import sys


ROUTING_INSTRUCTION = """Cost-optimized execution policy:

1. Start with a short plan + complexity triage on the current model.
2. If the task is small (roughly 1-3 files, existing pattern), do the work directly.
3. Escalate to the autopilot-opus subagent only for complex multi-file/architectural tasks after the plan is clear.
4. Run build/test before completion; use browser verification only if UI changed.
5. Never include Co-Authored-By lines in commit messages."""


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0

    prompt = payload.get("prompt", "")
    if not prompt:
        return 0

    # Skip injection for simple queries that don't need autopilot
    skip_keywords = [
        "what is",
        "explain",
        "how does",
        "tell me about",
        "describe",
        "list",
        "show me",
        "help",
        "?",
    ]

    prompt_lower = prompt.lower().strip()

    # Skip for very short prompts or questions
    if len(prompt_lower) < 20:
        return 0

    # Skip if it's just a question (starts with question word or ends with ?)
    question_starters = ["what", "why", "how", "when", "where", "who", "can", "is", "are", "do", "does"]
    if any(prompt_lower.startswith(q) for q in question_starters) and "?" in prompt:
        return 0

    # Skip if prompt already specifies routing/agents
    if "autopilot" in prompt_lower or "subagent" in prompt_lower or "plan first" in prompt_lower:
        return 0

    # Inject routing guidance using plain text hook output.
    print(ROUTING_INSTRUCTION)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
