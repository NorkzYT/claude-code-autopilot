# Claude Autopilot Task Template (copy/paste)

Fill in the 4 sections. Then paste the block below into Claude Code.

(Replace <...> placeholders with real text; remove unused sections.)

> **Ralph loops are automatically enabled.** When you use the autopilot subagent,
> it will iterate automatically until the Definition of Done is fully met.
> The task completes when autopilot outputs `<promise>TASK_COMPLETE</promise>`.

```text
Use the autopilot subagent.

1) GOAL (what you want)
- <One sentence goal>

2) DEFINITION OF DONE (how we know it’s finished)
- [ ] <Pass/fail result #1>
- [ ] <Pass/fail result #2>
- [ ] <Tests/lint/build pass OR specific manual check steps pass>

3) CONTEXT (optional and helpful)
- Product/area: <name>
- Constraints: no refactors; no network/destructive commands unless approved; follow repo patterns
- Suspected files/keywords (if you have them): <paths or terms>

4) DETAILS (paste everything relevant)
<<<
- Errors/logs:
  <paste>
- Repro steps (if bug):
  1) <step>
  2) <step>
- Expected vs actual:
  Expected: <...>
  Actual: <...>
- For architecture tasks, include requirements:
  - Scope IN: <...>
  - Scope OUT: <...>
  - Offline needs (storage/sync/conflicts): <...>
  - Environments (local/dev/stage/prod): <...>
>>>
```

---

## Two examples of “what to replace”

### Example A (bug)

**GOAL:** “Fix export crash and ensure WS products get eligibility quickly.”  
**DoD:**

- [ ] Export CSV/HTML does not throw `replace is not a function`
- [ ] WS products show eligibility counts correctly
- [ ] Verified by running the scanner on 5 pages and exporting

### Example B (architecture MVP)

**GOAL:** “Produce offline-first architecture + repo/env plan and minimal scaffolding docs.”  
**DoD:**

- [ ] Docs created: offline strategy + repo structure + env strategy
- [ ] Includes conflict resolution + failure modes
- [ ] `.env.example` + setup instructions added (if repo needs it)

---

## One rule that makes this work

When in doubt, put more into **DETAILS**. Autopilot is strongest when it has the raw error text, the exact UI text, and the real constraints.

---

## How automatic completion works

1. **You paste** the task template with `Use the autopilot subagent.`
2. **Autopilot starts** and automatically creates a Ralph loop (if not already active)
3. **Work proceeds** through the pipeline: plan -> implement -> verify -> review
4. **Iteration continues** automatically if verification fails or DoD is not met
5. **Task completes** when closer confirms DoD and outputs `<promise>TASK_COMPLETE</promise>`

Default settings: 30 max iterations, TASK_COMPLETE promise.

To manually control iterations, use `/ralph-loop` or `/ship` commands instead.
