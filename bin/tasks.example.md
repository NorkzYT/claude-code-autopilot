# Tasks

# Example task file consumed by `.claude/scripts/engineering-loop.sh`.
#
# Format
# ------
# Each task starts with "## Task: <slug>". The slug is used to identify the
# task across runs and feeds the default branch name (`feat/<slug>`).
#
# Two metadata lines follow the header:
#   **Status:**  pending | in-progress | done | failed
#   **Branch:**  <git-branch>            (optional; defaults to feat/<slug>)
#
# Everything after the blank line and before the trailing `---` separator
# is treated as the free-form task description and passed verbatim to the
# Claude session (and to the CrewAI planner when `--use-planner` is on).
#
# Run examples:
#   bash .claude/scripts/engineering-loop.sh --dry-run bin/tasks.example.md
#   bash .claude/scripts/engineering-loop.sh --use-planner bin/tasks.example.md
#   bash .claude/scripts/engineering-loop.sh --max-retries 5 bin/tasks.example.md

## Task: add-jwt-auth
**Status:** pending
**Branch:** feat/add-jwt-auth

Implement JWT authentication for the API endpoints. The system currently has no auth.
Users must log in with email/password and receive a JWT token. Protected routes must
reject requests without a valid token with 401. Add unit tests covering: successful
login, wrong-password rejection, missing-token rejection, and expired-token rejection.

---

## Task: add-rate-limiting
**Status:** pending
**Branch:** feat/add-rate-limiting

Add rate limiting middleware: 100 requests/minute per IP. Return 429 with a
`Retry-After` header (seconds) when the limit is exceeded. Allowlist health-check
routes so they never count against the limit. Cover the new behaviour with tests.

---

## Task: refactor-config-loader
**Status:** pending
**Branch:** chore/refactor-config-loader

Replace the ad-hoc `os.environ` reads scattered across the codebase with a single
`config.load()` helper that returns a typed `Config` dataclass. Update existing
callers to use the helper. Keep behaviour identical; add a regression test that
asserts the same env vars are honoured.

---
