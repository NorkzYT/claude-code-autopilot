# Claude Code Constitution

> This is the root context file. Keep it under 200 lines. Domain-specific guidance lives in subdirectory CLAUDE.md files.

## Universal Rules

1. **Smallest change that satisfies the task.** No drive-by refactors.
2. **Discovery first:** Search/read before deciding. Use `rg` and `Read` tools.
3. **Follow existing patterns.** Match the repo's style, naming, and structure.
4. **Always verify:** Run repo checks (tests/lint/build) or provide explicit manual steps.
5. **No network or destructive commands** unless explicitly approved by the user.

## Logging Convention

When adding logs, use: `internalLog.{debug,info,warn,error}`

## Reference Pointers (Just-in-Time Loading)

Instead of embedding full docs, load on-demand:

| Topic | Reference |
|-------|-----------|
| Workflow guide | Read `.claude/WORKFLOW.md` |
| Agent catalog | Read `.claude/agents/CLAUDE.md` |
| Hook documentation | Read `.claude/hooks/CLAUDE.md` |
| Session state | Read `.claude/docs/session-state.md` |
| Sentinel zones | Read `.claude/docs/sentinel-zones.md` |
| OpenClaw integration | Read `.claude/docs/openclaw-integration.md` |
| Browser login patterns | Read `.claude/skills/openclaw-browser/LOGIN_PATTERNS.md` |
| Extension testing | Read `.claude/skills/openclaw-browser/EXTENSION_TESTING.md` |

## Hierarchical Context Architecture

```
.claude/
├── CLAUDE.md              # Constitution (this file)
├── agents/
│   ├── CLAUDE.md          # Agent-specific guidance
│   └── *.md               # Individual agents
├── hooks/
│   ├── CLAUDE.md          # Hook-specific guidance
│   └── *.py               # Hook implementations
├── docs/
│   ├── session-state.md   # Three-file pattern docs
│   └── sentinel-zones.md  # Protected code zones
└── context/               # Session state (gitignored)
    └── <task>/
        ├── plan.md        # High-level plan
        ├── context.md     # Key learnings
        └── tasks.md       # Granular checklist
```

## High-Success Execution (Ralph Loops)

For guaranteed task completion, use **Ralph loops** as the default execution mode.

**Recommended**: Use `/ship` for fire-and-forget execution:
```
/ship "Build a REST API with tests"
```

This wraps the autopilot pipeline with a Ralph loop that continues until `<promise>TASK_COMPLETE</promise>` is output.

### Completion Promise Protocol

- Tasks running in Ralph loops must output `<promise>TASK_COMPLETE</promise>` when done
- The closer agent is the final gate that decides if the task is truly complete
- Loop continues automatically if the promise is not output

### Manual Ralph Loop

For custom iteration limits or promises:
```
/ralph-loop 20 TESTS_PASS "Make all tests pass"
```

## Default Agents

For complex multi-file architectural tasks, use the **autopilot** subagent:
```
Use the autopilot subagent (Task tool with subagent_type=autopilot) for this task
```

For simpler tasks (1-3 files, following existing patterns), work directly -- no sub-agent needed.

For parallel multi-part tasks, use the **parallel-orchestrator** subagent.

For planning without execution, use the **orchestrator** subagent (forced delegation).

## Sentinel Zones (Do Not Modify Without Explicit Approval)

Protected areas that require explicit user approval before modification:
- `.env*` files (except `.env.example`, `.env.sample`, `.env.template`)
- `**/secrets/**`, `**/*secret*`, `**/*credentials*`
- `**/prod/**`, `**/production/**` configurations
- `**/*.pem`, `**/*.key` (certificate material)
- Code marked with `LEGACY_PROTECTED`, `DO_NOT_MODIFY`, or `SECURITY_CRITICAL` comments

See `.claude/docs/sentinel-zones.md` for full configuration.

## Session Resilience (Three-File Pattern)

For complex tasks spanning multiple sessions:

1. **plan.md** - High-level architectural plan (the North Star)
2. **context.md** - Scratchpad of key learnings, decisions, gotchas
3. **tasks.md** - Granular checklist of remaining work

Store in `.claude/context/<task-name>/` directory.

Use `Document & Clear` cycle: After major milestones, persist state to files before proceeding.

## Security Checks

For code handling input/auth/data:
- Spawn `security-auditor` agent for vulnerability analysis
- Spawn `threat-modeling-expert` for architecture-level concerns
- Check `.claude/hooks/guard_bash.py` for blocked patterns

## Subdirectory Context Loading

Claude Code automatically loads CLAUDE.md from subdirectories when working in those areas:
- Working in agents? → `.claude/agents/CLAUDE.md` is loaded
- Working in hooks? → `.claude/hooks/CLAUDE.md` is loaded

This enables domain-specific guidance without bloating the root Constitution.

---

*This Constitution is the foundation. For detailed guidance, follow the Reference Pointers above.*
