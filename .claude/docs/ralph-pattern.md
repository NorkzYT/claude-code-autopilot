# Ralph Pattern — Multi-Session Iterative Development

## The Problem: Context Rot

LLMs get progressively less effective in long conversations. As the context window fills, the model loses focus, repeats mistakes, and drifts from the original task. This is **context rot**.

> "The LLM gets dumber the longer the conversation goes on, so have shorter conversations."

## The Solution: Fresh Sessions Per Iteration

The **Ralph pattern** (named after Ralph Wiggum — "I'm helping!") runs `claude -p` in an external bash loop. Each iteration starts a **fresh session** with zero prior context, reads a PRD + progress file, completes ONE task, commits, updates progress, and exits.

This completely eliminates context rot because each iteration has a pristine context window.

## Two Modes

### Multi-Session Ralph (Recommended)

External bash loop. Fresh `claude -p` session per iteration. No context rot.

```
make ralph-afk PRD=./PRD.md ITERATIONS=20
```

**When to use:**
- Complex multi-task PRDs (3+ tasks)
- AFK execution (overnight, lunch break)
- Tasks requiring many iterations
- When you've observed context rot in long sessions

**Scripts (also available as Makefile targets):**
- `ralph-once.sh` — Single iteration (HITL mode) -- `make ralph-once PRD=./PRD.md`
- `afk-ralph.sh` — Full AFK loop -- `make ralph-afk PRD=./PRD.md ITERATIONS=15`
- `ralph-docker.sh` — Docker sandbox wrapper

### Session Ralph (Legacy)

Hook-based (`ralph_loop_hook.py`). Blocks session exit and re-injects prompts in the **same session**. Prone to context rot but useful for quick in-session iteration.

```
/ralph-loop 10 TESTS_PASS "Make all tests pass"
```

**When to use:**
- Quick 2-3 iteration fixes
- Tasks that need the current session's context
- When Docker/subprocess overhead isn't worth it

## Decision Matrix

| Scenario | Mode | Why |
|----------|------|-----|
| New feature (5+ tasks) | Multi-Session | Fresh context per task |
| Bug fix (1-2 iterations) | Session | Stay in context |
| AFK overnight run | Multi-Session | Guaranteed fresh sessions |
| Refactor pass | Multi-Session | Each file gets full attention |
| "Make tests pass" loop | Session | Fast iteration, minimal overhead |
| CI/CD pipeline | Multi-Session + Docker | Isolation + reproducibility |

## PRD Writing Guide

Good PRDs are the key to Ralph success. The agent reads the PRD fresh each iteration, so it must be self-contained.

### Structure

```markdown
# PRD: Task Name

## Objective — One sentence. What are we building?
## Context — What does the agent need to know?
## Requirements — What must be true when done?
## Task Queue — Numbered, ordered, one-at-a-time tasks
## Acceptance Criteria — How do we know it's done?
## Constraints — What NOT to do
## Validation — Commands to verify
```

### Task Queue Rules

1. **One task = one commit.** Break work into the smallest units that produce a working commit.
2. **Order matters.** Task 1 should work without Task 2 existing.
3. **Be specific.** "Add user model" not "Set up backend".
4. **Include file hints.** "Add handler in `src/handlers/user.ts`" helps the agent find the right place.

### Examples

**Simple PRD (3 tasks):**
```markdown
# PRD: Add health check endpoint

## Objective
Add a /health endpoint that returns service status.

## Task Queue
1. [ ] Create GET /health route returning {"status":"ok","timestamp":"..."}
2. [ ] Add test for /health endpoint
3. [ ] Add /health to API documentation
```

**Medium PRD (6 tasks):**
```markdown
# PRD: User authentication

## Objective
Add JWT-based authentication with login/register endpoints.

## Context
- Express app in src/app.ts
- PostgreSQL via Prisma ORM
- Existing pattern: src/routes/*.ts, src/middleware/*.ts

## Task Queue
1. [ ] Add User model to Prisma schema with email, passwordHash, createdAt
2. [ ] Create auth middleware in src/middleware/auth.ts
3. [ ] Add POST /auth/register endpoint
4. [ ] Add POST /auth/login endpoint returning JWT
5. [ ] Add GET /auth/me endpoint (protected)
6. [ ] Add tests for all auth endpoints
```

**Complex PRD (10+ tasks):**
- Split into multiple PRDs
- Or use phases: PRD-phase1.md, PRD-phase2.md
- Run one afk-ralph per phase

## Progress File Format

The progress file is appended to (never overwritten) by each iteration:

```
=== Iteration 1 (2026-03-04T10:00:00Z) ===
Task: Set up basic project scaffolding
Done:
- Created src/index.ts
- Added package.json with dependencies
- Basic test harness working
Files changed: src/index.ts, package.json, tsconfig.json
Commit: abc1234
Next: Implement core feature X

=== Iteration 2 (2026-03-04T10:15:00Z) ===
Task: Implement core feature X
Done:
- Added handler in src/handler.ts
- 3 tests passing
Files changed: src/handler.ts, tests/handler.test.ts
Commit: def5678
Next: Add error handling
```

## Quick Start

### 1. Create a PRD

```bash
cp .claude/templates/PRD-template.md ./PRD.md
# Edit PRD.md with your task
```

### 2. Run one iteration (HITL)

```bash
make ralph-once PRD=./PRD.md
# Or directly: .claude/scripts/ralph-once.sh . ./PRD.md
```

### 3. Run AFK loop

```bash
make ralph-afk PRD=./PRD.md ITERATIONS=15
# Or directly: .claude/scripts/afk-ralph.sh --prd ./PRD.md --iterations 15
```

### 4. Run in Docker sandbox

```bash
.claude/scripts/afk-ralph.sh --prd ./PRD.md --iterations 15 --docker
```

### 5. Use via skill

```
/afk-ralph 20 "Build REST API with auth"
/ralph-once
/ralph-status
```

## Troubleshooting

### "No messages returned" bug

Claude CLI occasionally returns empty output. The loop handles this by treating it as a transient error and retrying. After 3 consecutive errors, the loop stops.

### Credential issues in Docker

Claude credentials are stored in a named Docker volume (`ralph-credentials`). If you get auth errors:

```bash
# Re-authenticate
docker compose -f docker-compose.ralph.yml run --rm ralph claude auth login
```

### Progress file gets corrupted

The agent appends to `progress.txt`. If it gets malformed, the next iteration still reads the PRD task queue directly — progress is advisory, not blocking.

### Docker build fails

```bash
# Rebuild without cache
docker compose -f docker-compose.ralph.yml build --no-cache ralph
```

### Agent skips tasks or combines them

Strengthen the PRD constraints section:
```markdown
## Constraints
- ONLY do ONE task per iteration
- Do NOT combine tasks
- If unsure which task is next, re-read progress.txt
```
