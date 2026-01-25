#!/usr/bin/env python3
"""
Auto-inject autopilot subagent instruction on every prompt.

This replicates the behavior of ~/.claude/CLAUDE.md but at project level.
The hook runs on UserPromptSubmit and injects the autopilot instruction.
"""
import json
import sys


AUTOPILOT_INSTRUCTION = """Use the autopilot subagent (Task tool with subagent_type=autopilot) for this task.

IMPORTANT: Launch the autopilot agent to handle this request. Do not attempt to do the work directly."""


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

    # Skip if prompt already mentions autopilot or agents
    if "autopilot" in prompt_lower or "subagent" in prompt_lower:
        return 0

    # Inject the autopilot instruction using correct hook schema
    # Plain text to stdout is the simplest way to add context
    print(AUTOPILOT_INSTRUCTION)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
