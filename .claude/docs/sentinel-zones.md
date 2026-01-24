# Sentinel Zones Configuration

Sentinel zones are protected areas of code that require explicit user approval before modification.

## Purpose

Protect critical code from accidental modification:
- Production configurations
- Security-sensitive files
- Legacy code with implicit dependencies
- Files with regulatory/compliance implications

## Protected Patterns

### Sensitive Files (Always Protected)

```python
# From protect_files.py PROTECTED_GLOBS
PROTECTED_GLOBS = [
    # Environment files
    "**/.env",
    "**/.env.*",

    # Key/certificate material
    "**/*.pem",
    "**/*.key",
    "**/*.p12",
    "**/*.pfx",
    "**/id_rsa",
    "**/id_rsa.*",
    "**/id_ed25519",
    "**/id_ed25519.*",

    # Secret files
    "**/*secret*",
    "**/*secrets*",
    "**/.aws/**",
    "**/.ssh/**",
    "**/*kubeconfig*",

    # Production configurations
    "**/docker-compose.prod*.yml",
    "**/docker-compose.production*.yml",
    "**/.github/workflows/*deploy*.yml",
    "**/infra/prod/**",
    "**/k8s/prod/**",
    "**/terraform/prod/**",
    "**/config/prod/**",
    "**/config/production/**",
]
```

### Allowed Exceptions

```python
# Safe to edit even if they match protected globs
ALLOWED_PATTERNS = [
    "**/.env.example",
    "**/.env.sample",
    "**/.env.template",
    "**/docker-compose.prod*.yml",  # If tracked in git
    "**/docker-compose.production*.yml",
]
```

## Code-Level Sentinel Markers

Mark specific code blocks as protected using these markers:
- `LEGACY_PROTECTED` - Legacy code with implicit dependencies
- `DO_NOT_MODIFY` - Code that should not be changed without review
- `SECURITY_CRITICAL` - Security-sensitive code requiring security review

### Python
```python
# SECURITY_CRITICAL: Critical auth logic - do not modify without security review
def verify_token(token):
    ...

# LEGACY_PROTECTED: Handles edge case from 2019 incident #1234
def legacy_handler():
    ...
```

### JavaScript/TypeScript
```javascript
// SECURITY_CRITICAL: Payment processing - PCI compliance
function processPayment(card) {
    ...
}

/* LEGACY_PROTECTED: Safari iOS workaround - do not remove */
function safariPolyfill() {
    ...
}
```

### Go
```go
// DO_NOT_MODIFY: Rate limiting logic - production tuned
func rateLimiter(ctx context.Context) {
    ...
}
```

Note: Markers are only detected in code files (.py, .js, .ts, .go, etc.), not in documentation or configuration files.

## Detecting Sentinel Markers

Use grep to find sentinel zones:

```bash
# Find all sentinel markers
rg "LEGACY_PROTECTED|DO_NOT_MODIFY|SECURITY_CRITICAL" --type-add 'code:*.{py,js,ts,go,java,rs}' -t code

# Find in specific directory
rg "LEGACY_PROTECTED" src/
```

## Adding New Protected Patterns

Edit `.claude/hooks/protect_files.py`:

```python
# Add to PROTECTED_GLOBS
PROTECTED_GLOBS = [
    ...existing patterns...
    # Custom patterns
    "**/compliance/**",
    "**/billing/**",
    "**/audit/**",
]
```

## Temporary Override

For legitimate modifications:

```bash
# Set environment variable before starting Claude
export CLAUDE_ALLOW_PROTECTED_EDITS=1
```

Then restart Claude Code. Remember to unset after:

```bash
unset CLAUDE_ALLOW_PROTECTED_EDITS
```

## Sentinel Zone Workflow

When Claude needs to modify a sentinel zone:

1. **Detection**: Hook blocks the edit
2. **Notification**: User sees why edit was blocked
3. **Review**: User reviews the proposed change
4. **Decision**:
   - Approve: Set override env var, restart Claude
   - Reject: Ask Claude for alternative approach
   - Defer: Mark as follow-up for manual implementation

## Best Practices

### Do Mark as Sentinel
- Authentication/authorization logic
- Payment/financial processing
- Cryptographic implementations
- Rate limiting/throttling
- Audit logging
- Compliance-related code
- Legacy workarounds with unknown dependencies

### Don't Mark as Sentinel
- Regular business logic
- UI components
- Test files
- Documentation
- Non-production configurations

## Integration with Code Review

Sentinel zones should trigger additional review:
- Security team review for auth/crypto changes
- Compliance review for audit/regulatory changes
- Architecture review for core infrastructure changes

## Monitoring

Track sentinel zone modifications:

```bash
# Git log for protected paths
git log --oneline -- '**/prod/**' '**/.env*' '**/secrets/**'

# Grep Claude logs for blocked edits
grep "Blocked edit to protected file" .claude/logs/*.log
```
