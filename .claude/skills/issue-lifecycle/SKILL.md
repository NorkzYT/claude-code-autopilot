---
name: issue-lifecycle
description: Close resolved issues and surface next bugs after a fix is deployed.
tags: [git, github, workflow, issues]
---

# Issue Lifecycle Skill

After a fix is verified and deployed, this skill handles issue closure and surfaces the next work item.

## When to Use

- After autopilot step 8b (deploy) succeeds
- After closer confirms all checks pass
- When the user asks "what's next?" after a fix

## Workflow

1. **Close the resolved issue** (if issue number is known):
   ```
   gh issue close <num> --comment "Fixed in <sha>. Verified via lifecycle checks (build/test/confirm pass)."
   ```

2. **List next open issues** (prioritize bugs):
   ```
   gh issue list --label "bug" --state open --limit 5
   ```
   If no bugs, fall back to:
   ```
   gh issue list --state open --limit 5
   ```

3. **Present options to the user**:
   - Show issue titles, labels, and assignees
   - Ask which issue to work on next (or if they want to stop)

## Integration with Autopilot

The closer agent can optionally invoke this skill as a final step:
- Only when running on a repo with GitHub Issues enabled
- Only when the original task referenced an issue number
- Present the next-issue list as informational (don't auto-start work)

## Guard Rails

- Never close an issue without a verified fix (all lifecycle checks must pass)
- Never auto-assign or auto-start work on the next issue without user confirmation
- If `gh` CLI is not available or not authenticated, skip gracefully and report
