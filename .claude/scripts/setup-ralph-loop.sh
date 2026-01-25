#!/bin/bash
#
# Setup Ralph Wiggum iterative loop.
#
# Usage:
#   setup-ralph-loop.sh [max_iterations] [completion_promise]
#
# The prompt text should be provided via stdin or as the remaining arguments.
#
# Examples:
#   echo "Implement feature X until it passes all tests" | ./setup-ralph-loop.sh 10 TESTS_PASS
#   ./setup-ralph-loop.sh 20 DONE "Refactor the codebase until all linting passes"
#

set -e

# Defaults
MAX_ITERATIONS="${1:-20}"
COMPLETION_PROMISE="${2:-DONE}"
shift 2 2>/dev/null || true

# State file location
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
STATE_FILE="$PROJECT_DIR/.claude/ralph-loop.local.md"

# Get prompt from arguments or stdin
if [ $# -gt 0 ]; then
    PROMPT="$*"
elif [ ! -t 0 ]; then
    PROMPT=$(cat)
else
    echo "Error: No prompt provided. Pass as argument or via stdin." >&2
    echo "Usage: $0 [max_iterations] [completion_promise] \"prompt text\"" >&2
    exit 1
fi

if [ -z "$PROMPT" ]; then
    echo "Error: Prompt cannot be empty." >&2
    exit 1
fi

# Create directory if needed
mkdir -p "$(dirname "$STATE_FILE")"

# Idempotency check: don't overwrite active loops
if [ -f "$STATE_FILE" ]; then
    # Check if loop is active using grep
    if grep -q "^active: true" "$STATE_FILE" 2>/dev/null; then
        echo "Ralph loop already active. Skipping setup."
        echo "  State file: $STATE_FILE"
        echo "  To restart, first run: cancel-ralph-loop.sh"
        exit 0
    fi
fi

# Generate state file with YAML frontmatter
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

cat > "$STATE_FILE" << EOF
---
active: true
iteration: 1
max_iterations: $MAX_ITERATIONS
completion_promise: "$COMPLETION_PROMISE"
started_at: "$TIMESTAMP"
---

$PROMPT
EOF

echo "Ralph loop initialized:"
echo "  State file: $STATE_FILE"
echo "  Max iterations: $MAX_ITERATIONS"
echo "  Completion promise: $COMPLETION_PROMISE"
echo "  Prompt: ${PROMPT:0:100}..."
echo ""
echo "The loop will run until:"
echo "  1. Claude outputs <promise>$COMPLETION_PROMISE</promise>, or"
echo "  2. Max iterations ($MAX_ITERATIONS) is reached"
echo ""
echo "To cancel: run 'cancel-ralph-loop.sh' or delete $STATE_FILE"
