#!/usr/bin/env python3
"""
UserPromptSubmit hook that injects autopilot instructions into every prompt.
Outputs JSON with additionalContext to make Claude use the autopilot subagent.
"""
import json

print(json.dumps({
    "additionalContext": "Use the autopilot subagent (Task tool with subagent_type=autopilot) for this task."
}))
