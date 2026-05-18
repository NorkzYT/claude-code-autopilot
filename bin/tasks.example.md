# Tasks

# Example task file consumed by `.claude/scripts/engineering-loop.sh`.
#
# Format
# ------
# Each task starts with "## Task: <slug>". The slug identifies the task across
# runs and feeds the default branch name (`feat/<slug>`).
#
# Metadata lines follow the header:
#   **Status:**  pending | in-progress | done | failed
#   **Type:**    coding | research | creative | personal | marketing | auto | <custom>
#                (optional; defaults to "coding")
#   **Branch:**  <git-branch>    (optional; only used for coding tasks)
#
# Everything after the blank line and before the trailing `---` separator
# is the free-form task description passed to the execution engine.
#
# Routing:
#   coding (default) — executed via claude-max-proxy (Claude Code subscription).
#                      Tests run automatically, retried on failure, committed.
#   research / creative / personal / marketing / auto — routed to the CrewAI
#                      multi-crew system (Codex via CLIProxyAPI). Output written
#                      to bin/outputs/<slug>/result.md. No test loop, no commit.
#   <custom>         — matches a private crew in .crewai/crews/private/<custom>.py
#
# Run examples:
#   bash .claude/scripts/engineering-loop.sh --dry-run bin/tasks.example.md
#   bash .claude/scripts/engineering-loop.sh --use-planner bin/tasks.example.md
#   bash .claude/scripts/engineering-loop.sh bin/

## Task: add-jwt-auth
**Status:** pending
**Type:** coding
**Branch:** feat/add-jwt-auth

Implement JWT authentication for the API endpoints. The system currently has no auth.
Users must log in with email/password and receive a JWT token. Protected routes must
reject requests without a valid token with 401. Add unit tests covering: successful
login, wrong-password rejection, missing-token rejection, and expired-token rejection.

---

## Task: add-rate-limiting
**Status:** pending
**Type:** coding
**Branch:** feat/add-rate-limiting

Add rate limiting middleware: 100 requests/minute per IP. Return 429 with a
`Retry-After` header (seconds) when the limit is exceeded. Allowlist health-check
routes so they never count against the limit. Cover the new behaviour with tests.

---

## Task: refactor-config-loader
**Status:** pending
**Type:** coding
**Branch:** chore/refactor-config-loader

Replace the ad-hoc `os.environ` reads scattered across the codebase with a single
`config.load()` helper that returns a typed `Config` dataclass. Update existing
callers to use the helper. Keep behaviour identical; add a regression test that
asserts the same env vars are honoured.

---

## Task: research-api-auth-patterns
**Status:** pending
**Type:** research

Research modern API authentication patterns for a SaaS product. Compare:
- JWT vs session tokens vs API keys
- OAuth 2.0 / OIDC for user-facing flows
- HMAC request signing for service-to-service

Produce a decision matrix with trade-offs, security considerations, and a
recommendation for which pattern fits a B2B SaaS product with both a web app
and a machine API.

---
