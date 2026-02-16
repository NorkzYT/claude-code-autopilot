# Heartbeat Checklist

> Automated health checks run by OpenClaw on a schedule.
> Reports to Discord only when issues are found.

## Checks

### Git Status
- [ ] No uncommitted changes in tracked files
- [ ] Branch not diverged from remote
- [ ] No merge conflicts

### Test Suite
- [ ] Fast test suite passes (`npm test` / `pytest`)
- [ ] No new test failures since last check

### Dependency Security
- [ ] `npm audit` reports no high/critical vulnerabilities
- [ ] `pip audit` reports no known vulnerabilities (if Python project)

### Token Usage (Informational)
- [ ] Daily token usage within expected range
- [ ] Cache hit rate above 30%

### System Health
- [ ] Disk usage below 90%
- [ ] OpenClaw gateway running
- [ ] Memory usage within limits

## Report Format

When issues found, report to Discord:
```
HEARTBEAT: <project-name>
Issues found:
- [category] description
```

When all checks pass:
```
HEARTBEAT_OK (suppressed unless verbose mode)
```
