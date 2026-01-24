# Agent Catalog and Guidelines

This directory contains all agent definitions for the Claude Code autopilot system.

## Agent Architecture

Agents follow the **Orchestrator -> Explorer/Coder** pattern:
- **Orchestrator agents** plan and delegate (cannot directly modify code)
- **Explorer agents** investigate and report findings
- **Coder agents** implement changes with full tool access

## Available Agents

### Core Workflow Agents

| Agent | Purpose | Tools |
|-------|---------|-------|
| `autopilot` | One-shot delivery: plan -> implement -> verify -> review | Full access |
| `parallel-orchestrator` | Orchestrates parallel agent deployment | Read, Glob, Grep, Bash, Task |
| `orchestrator` | Planning only, forced delegation | Read, Glob, Grep, Task |
| `autopilot-fixer` | Fix-up pass for incomplete work | Full access |
| `closer` | Verification and PR-ready summary | Read, Glob, Grep, Bash, Task |

### Specialized Agents

| Agent | Purpose | Tools |
|-------|---------|-------|
| `promptsmith` | Converts raw tasks into execution-ready prompts | Read only |
| `shipper` | Lightweight inspect -> implement -> verify | Full access |
| `triage` | Debugging and root cause analysis | Read, Glob, Grep, Bash |
| `surgical-reviewer` | Code review focused on correctness | Read, Glob, Grep |
| `runbook` | Generates next-action prompts when stuck | Read only |

## Spawning Agents

Use the Task tool to spawn agents:

```
Task tool with subagent_type=<agent-name>
```

Example:
```
Use the autopilot subagent (Task tool with subagent_type=autopilot) for this task
```

## Agent Design Patterns

### 1. Forced Delegation Pattern

The `orchestrator` agent cannot directly access code. It must:
1. Analyze the task and decompose into subtasks
2. Spawn specialist agents for each subtask
3. Aggregate results from sub-agents
4. Report distilled context (not raw output)

### 2. Parallel Agent Deployment

When tasks have independent components:
- Fan-out: Spawn 2-4 agents for independent subtasks
- Pipeline: Run different stages in parallel
- Swarm: Multiple coders on different features

Bounded concurrency: Max 2-4 concurrent agents to avoid context confusion.

### 3. Context Store Pattern

Sub-agents work with full context but report only:
- Key findings (not full file contents)
- Decisions made (not exploration history)
- Verification results (pass/fail + summary)

This prevents context explosion in the parent agent.

## Creating New Agents

Agent files follow this frontmatter format:

```yaml
---
name: agent-name
model: opus
description: One-line purpose statement
tools: Read, Glob, Grep, Bash, Edit, Write, Task
---
```

After frontmatter, include:
1. Purpose statement
2. Hard rules (constraints)
3. Workflow (numbered steps)
4. Input/output format

## Agent Categories Reference

| Category | Agent Names |
|----------|-------------|
| Web/Frontend | `javascript-pro`, `typescript-pro` |
| Python Ecosystem | `python-pro`, `django-pro`, `fastapi-pro`, `temporal-python-pro` |
| Systems Languages | `golang-pro`, `rust-pro`, `c-pro`, `cpp-pro` |
| JVM Languages | `java-pro`, `scala-pro` |
| Other Languages | `csharp-pro`, `elixir-pro`, `haskell-pro` |
| Architecture | `architect-review`, `backend-architect`, `graphql-architect`, `event-sourcing-architect` |
| Security | `security-auditor`, `threat-modeling-expert` |
| Quality/Review | `code-reviewer`, `surgical-reviewer` |
| Testing | `test-automator`, `tdd-orchestrator` |
| Debugging | `debugger`, `triage` |
| DevOps | `deployment-engineer`, `performance-engineer` |
| Modernization | `legacy-modernizer`, `dx-optimizer` |
| Workflow | `autopilot-fixer`, `closer`, `runbook`, `promptsmith`, `shipper` |

To check installed agents: `ls .claude/agents/`
