#!/usr/bin/env python3
"""
UserPromptSubmit hook that assigns a random memorable name to each terminal session.

Generates a two-word name (adjective-animal) on first prompt, stores it in
.claude/terminal-identity.local.json, sets the terminal title, and prints
the name to stderr. Subsequent prompts in the same session are no-ops.
"""
import json
import os
import random
import sys
from datetime import datetime
from pathlib import Path

ADJECTIVES = [
    "cosmic", "thunder", "velvet", "neon", "shadow", "crystal", "phantom",
    "golden", "iron", "arctic", "blazing", "crimson", "mystic", "quantum",
    "swift", "silent", "brave", "clever", "fierce", "noble", "lunar",
    "solar", "frosty", "ember", "coral", "azure", "scarlet", "jade",
    "obsidian", "silver", "copper", "ruby", "amber", "ivory", "onyx",
    "turbo", "rapid", "primal", "vivid", "bold", "keen", "wild",
    "stormy", "dusty", "pixel", "cyber", "stealth", "sonic", "atomic",
    "radiant",
]

ANIMALS = [
    "penguin", "falcon", "panther", "wolf", "dragon", "phoenix", "tiger",
    "cobra", "raven", "hawk", "fox", "bear", "shark", "eagle", "lynx",
    "otter", "viper", "mustang", "jaguar", "puma", "dolphin", "mantis",
    "condor", "badger", "bison", "crane", "gecko", "heron", "ibex",
    "koala", "lemur", "moose", "narwhal", "osprey", "parrot", "quail",
    "raptor", "salmon", "toucan", "urchin", "walrus", "yak", "zebra",
    "coyote", "ferret", "gorilla", "hyena", "iguana", "jackal", "octopus",
]


def main() -> int:
    project_dir = os.getenv("CLAUDE_PROJECT_DIR") or os.getcwd()
    session_id = os.getenv("CLAUDE_SESSION_ID", "")
    identity_path = Path(project_dir) / ".claude" / "terminal-identity.local.json"

    # Check if identity already exists for this session
    if identity_path.exists():
        try:
            data = json.loads(identity_path.read_text(encoding="utf-8"))
            if data.get("session_id") == session_id:
                # Already set for this session, nothing to do
                return 0
        except (json.JSONDecodeError, OSError):
            pass

    # Generate a new name
    name = f"{random.choice(ADJECTIVES)}-{random.choice(ANIMALS)}"

    # Write identity file
    identity_path.parent.mkdir(parents=True, exist_ok=True)
    identity_path.write_text(
        json.dumps(
            {
                "session_id": session_id,
                "name": name,
                "created_at": datetime.utcnow().isoformat() + "Z",
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )

    # Set terminal title via ANSI escape
    sys.stderr.write(f"\033]0;Claude: {name}\007")
    # Print identity banner
    sys.stderr.write(f"\U0001f916 Terminal: {name}\n")
    sys.stderr.flush()

    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception:
        # Never block — always exit 0
        sys.exit(0)
