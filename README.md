# claude-autopilot-kit

A reusable `.claude/` setup for **Claude Code** that boosts one-shot task completion by enforcing a simple, repeatable pipeline:

**promptsmith → autopilot/shipper → (triage) → autopilot-fixer → closer**  
…with **permissions guardrails**, **auto-format on touched files (when configured)**, and **session logging**.

## What’s inside

### Agents (`.claude/agents/`)

- **promptsmith** — turns a raw request into a single execution-ready prompt (TODO + DoD + discovery + verification).
- **autopilot** — one-shot delivery: discover → implement → verify → review → (one retry if needed).
- **triage** — debugging when something fails (repro → evidence → smallest fix + verify).
- **autopilot-fixer** — “finish the job” pass when output is incomplete/wrong (single bounded patch loop).
- **closer** — verification + reviewer pass + PR-ready release notes (no new implementation).
- **shipper** — straightforward inspect → implement → verify (lighter than autopilot).
- **surgical-reviewer** — minimal-risk review of diffs; flags correctness + edge cases.

### Hooks (`.claude/hooks/`)

- **guard_bash.py** — blocks obviously dangerous bash patterns (e.g., `rm -rf`, pipe-to-shell).
- **format_if_configured.py** — formats the _edited file only_ when a formatter config exists:
  - JS/TS: runs Prettier if `.prettierrc*` exists
  - Python: runs Black if `pyproject.toml` exists
- **log_prompt.py / log_bash.py / log_assistant.py** — appends to `.claude/logs/*` for traceability.

### Settings (`.claude/settings.local.json`)

Tool permissions allowlist/denylist + hook wiring.

> Tip: Claude Code commonly reads project config from `.claude/settings.json`. If your install expects that, copy:
> `cp .claude/settings.local.json .claude/settings.json`

## Install (use this kit in another repo)

From the **target repo root** (the repo you want Claude to work on), bring in this kit’s `.claude/` folder:

### Option A — copy (simplest)

```bash
cp -R /path/to/claude-autopilot-kit/.claude .
```

### Option B — symlink (keeps it centralized)

```bash
ln -s /path/to/claude-autopilot-kit/.claude .claude
```

### Git hygiene

Add logs to `.gitignore` in your target repos:

```gitignore
.claude/logs/
```

## Recommended daily usage

### 1) Start Claude Code

Safer default (plan first):

```bash
claude --permission-mode plan
```

Then switch to execution:

```bash
claude --permission-mode ask
# or: claude --permission-mode allow  (only if you trust your allowlist + hooks)
```

### 2) Run a one-shot task (fast path)

Paste into Claude Code:

```text
Use the autopilot subagent.

1) GOAL
- <one sentence>

2) DEFINITION OF DONE
- [ ] <measurable outcome>
- [ ] <measurable outcome>
- [ ] Tests/lint/build pass OR exact manual steps pass

3) CONTEXT (optional)
- Constraints: minimal changes; follow repo patterns; no network/destructive commands unless approved
- Suspected files/keywords: <paths/terms>

4) DETAILS
<<<
<paste errors, repro steps, expected vs actual, requirements>
>>>
```

### 3) If it’s “mostly done” and still wrong

Use the bounded fix-up pass:

```text
Use the autopilot-fixer subagent.

Original Task:
<<<
<paste the kickoff prompt you used>
>>>

Prior Claude Output:
<<<
<paste Claude’s last summary / claims / changed files>
>>>

Observed Behavior / Logs:
<<<
<paste what’s still wrong + command output>
>>>
```

### 4) Close it out (verification + PR notes)

```text
Use the closer subagent.

DoD / Acceptance Criteria:
<<<
<paste DoD>
>>>

Changed Files:
<<<
<paste list or "unknown">
>>>
```

## Operating rules (the whole point of this kit)

- **Smallest change that satisfies the task** (no drive-by refactors).
- **Discovery first**: search/read before deciding.
- **Always verify**: run repo checks (tests/lint/build) or provide a precise manual checklist.
- **One bounded retry** when something fails (triage → patch → re-verify once).
- **No network or destructive commands unless you explicitly approve.**

## Customization (quick + safe)

- Want stricter permissions? tighten `.claude/settings*.json` allowlist.
- Want quieter diffs? disable `format_if_configured.py` or limit formatters.
- Want more auditing? keep logs on; rotate `.claude/logs/*` as needed.

## Troubleshooting

- **Hooks not running?** Ensure the settings file is the one Claude Code loads (`.claude/settings.json` vs `settings.local.json`).
- **Formatting didn’t happen?** Prettier requires `.prettierrc*`; Black requires `pyproject.toml`.
- **A command got blocked?** Check `.claude/hooks/guard_bash.py` patterns and adjust intentionally.
