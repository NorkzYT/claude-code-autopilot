# After Autopilot: Automatic Fix (copy/paste)

Paste into Claude Code:

```text
Use the autopilot-fixer subagent.

Original Task:
<<<
<PASTE the exact kickoff prompt you used (from WORKFLOW_EXAMPLE.md)>
>>>

Prior Claude Output:
<<<
<PASTE Claude’s final response + any “verified” claims + files changed>
>>>

Observed Behavior / Logs:
<<<
What’s still wrong (pick one or more):
- Expected: <...>
- Actual: <...>
- Errors / failing tests / console output: <paste>
- Repro steps:
  1) <...>
  2) <...>
- Verification commands you ran + output:
  <paste>
>>>
```

---

## How your flow becomes “0 → 1 → correct”

1. Paste `WORKFLOW_EXAMPLE.md` (autopilot kickoff)
2. If not correct: paste `WORKFLOW_FIX_AUTOMATIC.md` (autopilot-fixer)  
   Done.

No deciding triage vs runbook manually.

---

### One small improvement I’d also do

Rename your agents to make the mental model obvious for new people:

- `autopilot` = build/fix from scratch
- `autopilot-fixer` = repair/finish pass
- `promptsmith` = prompt generator
- `surgical-reviewer` = safety review

---

