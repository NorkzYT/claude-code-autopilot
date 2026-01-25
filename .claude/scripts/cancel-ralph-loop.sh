#!/bin/bash
#
# Cancel an active Ralph Wiggum iterative loop.
#
# Usage:
#   cancel-ralph-loop.sh
#
# This script deactivates the loop by setting active: false in the state file.
# The state file is preserved for debugging/history purposes.
#

set -e

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
STATE_FILE="$PROJECT_DIR/.claude/ralph-loop.local.md"

if [ ! -f "$STATE_FILE" ]; then
    echo "No Ralph loop state file found at: $STATE_FILE"
    echo "Nothing to cancel."
    exit 0
fi

# Check if already inactive
if grep -q "^active: false" "$STATE_FILE" 2>/dev/null; then
    echo "Ralph loop is already inactive."
    exit 0
fi

# Deactivate by replacing active: true with active: false
if command -v sed &> /dev/null; then
    # Add end timestamp and reason
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Use temp file for safe in-place edit
    TEMP_FILE=$(mktemp)

    # Replace active: true with active: false and add end info
    sed 's/^active: true/active: false/' "$STATE_FILE" | \
    sed "/^active: false/a ended_at: \"$TIMESTAMP\"\nend_reason: \"user_cancelled\"" > "$TEMP_FILE"

    mv "$TEMP_FILE" "$STATE_FILE"

    echo "Ralph loop cancelled."
    echo "  State file preserved at: $STATE_FILE"
    echo "  To fully remove: rm $STATE_FILE"
else
    # Fallback: just remove the file
    rm "$STATE_FILE"
    echo "Ralph loop cancelled (state file removed)."
fi
