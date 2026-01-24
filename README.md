# claude-autopilot-kit

A reusable `.claude/` setup for **Claude Code** that boosts one-shot task completion by enforcing a simple, repeatable pipeline:

**promptsmith → autopilot/shipper → (triage) → autopilot-fixer → closer**
…with **permissions guardrails**, **supply-chain security**, **auto-format on touched files**, and **session logging**.

Optionally integrates curated agents/commands from [wshobson/commands](https://github.com/wshobson/commands) and [wshobson/agents](https://github.com/wshobson/agents) for additional productivity operators.

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

- **guard_bash.py** — blocks dangerous bash patterns + supply-chain attacks:
  - Destructive commands: `rm -rf`, `sudo`, `mkfs`
  - Remote code execution: `curl|bash`, `wget|sh`, base64-to-shell
  - Supply-chain: `npx` (hallucinated packages), `npm install` (postinstall scripts), `pip install` from URLs
  - Allowlist support for trusted packages
- **format_if_configured.py** — formats the _edited file only_ when a formatter config exists:
  - JS/TS: runs Prettier if `.prettierrc*` exists
  - Python: runs Black if `pyproject.toml` exists
- **log_prompt.py / log_bash.py / log_assistant.py** — appends to `.claude/logs/*` for traceability.

### Extras (`.claude/extras/`)

- **install-extras.sh** — vendor-sync installer for external repos (wshobson commands/agents)
- **doctor.sh** — validates `.claude/` configuration, settings schema, and hooks

### Scripts (`.claude/scripts/`)

- **install-opencode-ohmy.sh** — optional installer for OpenCode + oh-my-opencode (separate toolchain, see ToS warning)

### Settings (`.claude/settings.local.json`)

Tool permissions allowlist/denylist + hook wiring.

> Tip: Claude Code commonly reads project config from `.claude/settings.json`. If your install expects that, copy:
> `cp .claude/settings.local.json .claude/settings.json`

## Install (use this kit in another repo)

> **Warning**: Do not run as root user. Install and run this kit as a non-root user only.

From the **target repo root** (the repo you want Claude to work on), bring in this kit's `.claude/` folder:

### Option 0 — full bootstrap (recommended for Linux)

Installs everything: `.claude/` (includes extras, scripts), devtools (git, rsync, python3), and wshobson agents/commands:

```bash
curl -fsSL https://raw.githubusercontent.com/NorkzYT/claude-code-autopilot/main/install.sh \
  | bash -s -- --repo NorkzYT/claude-code-autopilot --ref main --force --bootstrap-linux
```

This runs:
1. `linux_devtools.sh` — installs git, rsync, python3, notify-send, LSP binaries
2. `install-extras.sh` — clones and syncs wshobson commands/agents/skills

### Option 1 — kit only (no extras)

```bash
curl -fsSL https://raw.githubusercontent.com/NorkzYT/claude-code-autopilot/main/install.sh \
  | bash -s -- --repo NorkzYT/claude-code-autopilot --ref main --force
```

Or with bootstrap but without wshobson extras:

```bash
curl -fsSL https://raw.githubusercontent.com/NorkzYT/claude-code-autopilot/main/install.sh \
  | bash -s -- --repo NorkzYT/claude-code-autopilot --ref main --force --bootstrap-linux --no-extras
```

### Installer options

| Option | Description |
|--------|-------------|
| `--repo <owner/repo>` | Source repo (required) |
| `--ref <branch\|tag\|sha>` | Git ref (default: main) |
| `--dest <path>` | Destination directory (default: current directory) |
| `--force` | Overwrite existing `.claude/` (preserves logs) |
| `--bootstrap-linux` | Run full bootstrap (devtools + extras) |
| `--no-extras` | Skip wshobson agents/commands/skills |

#### Updating an existing install

To update/refresh the kit, run the **same install command** again with `--force`:

```bash
curl -fsSL https://raw.githubusercontent.com/NorkzYT/claude-code-autopilot/main/install.sh \
  | bash -s -- --repo NorkzYT/claude-code-autopilot --ref main --force --bootstrap-linux
```

Notes:

* `--force` overwrites the kit files to match the latest version, while preserving your local `.claude/logs/`.
* If you want to pin to a specific version, replace `--ref main` with a tag or commit SHA.

### Option A — copy (simplest)

```bash
cp -R /path/to/claude-autopilot-kit/.claude .
```

### Option B — symlink (keeps it centralized)

```bash
ln -s /path/to/claude-autopilot-kit/.claude .claude
```

### Git hygiene

Add these to `.gitignore` in your target repos:

```gitignore
.claude/logs/
.claude/vendor/
.claude/commands/tools/
.claude/commands/workflows/
.claude/skills/wshobson-*
```

## Extras (wshobson integration)

When installed with `--bootstrap-linux`, you get curated agents and commands from:
- [wshobson/commands](https://github.com/wshobson/commands) — `/tools:...` and `/workflows:...` operators
- [wshobson/agents](https://github.com/wshobson/agents) — 72 specialized plugins (14 installed by default)

### Default plugins installed

| Category | Plugins |
|----------|---------|
| **Workflow** | full-stack-orchestration, comprehensive-review, security-scanning, backend-development |
| **Languages** | javascript-typescript, python-development, systems-programming (Go/Rust/C++), jvm-languages, functional-programming |
| **Quality** | debugging-toolkit, code-refactoring, unit-testing, tdd-workflows, git-pr-workflows |

To install additional plugins, edit `WSHOBSON_AGENT_PLUGINS` in `.claude/extras/install-extras.sh`. See [all 72 plugins](https://github.com/wshobson/agents/tree/main/plugins).

### Usage examples

```text
/workflows:full-stack-feature build user authentication
/tools:security-scan src/
```

### Manual extras management

```bash
# Install/update extras manually
./.claude/extras/install-extras.sh

# Update existing vendor repos
./.claude/extras/install-extras.sh --update

# Install specific components only
./.claude/extras/install-extras.sh --commands    # wshobson/commands only
./.claude/extras/install-extras.sh --agents      # wshobson/agents only

# Show CLI tools guide (viwo, recall, ccusage, etc.)
./.claude/extras/install-extras.sh --cli-info
```

### Validate configuration

```bash
./.claude/extras/doctor.sh
```

Checks JSON syntax, settings schema, hook scripts, agent frontmatter, and common issues.

## Optional: OpenCode + oh-my-opencode

A separate toolchain installer is provided for [OpenCode](https://opencode.ai/) + [oh-my-opencode](https://github.com/code-yeongyu/oh-my-opencode):

```bash
./.claude/scripts/install-opencode-ohmy.sh
```

> **Warning**: oh-my-opencode is designed for OpenCode, not Claude Code. The README warns about OAuth/ToS implications when used with Claude Code accounts. This installs as a completely separate toolchain.

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
- **Formatting didn't happen?** Prettier requires `.prettierrc*`; Black requires `pyproject.toml`.
- **A command got blocked?** Check `.claude/hooks/guard_bash.py` patterns and adjust intentionally.
- **npx/npm blocked?** Supply-chain guardrails block these by default. Add trusted packages to the allowlist in `guard_bash.py`.
- **Configuration issues?** Run `./.claude/extras/doctor.sh` to validate your setup.
- **Extras not installed?** Run `./.claude/extras/install-extras.sh` manually, or reinstall with `--bootstrap-linux`.
