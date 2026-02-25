# Browser Login Patterns

> Authentication strategies for OpenClaw browser automation.

## Strategy 1: Cookie Import/Export (Recommended)

The safest and most reliable authentication method.

### Initial Setup (Manual, One-Time)

1. Start the OpenClaw-managed browser:
   ```bash
   openclaw browser --browser-profile openclaw start
   ```
2. Navigate to the target site:
   ```bash
   openclaw browser navigate "https://keepa.com"
   ```
3. Log in manually (use `openclaw browser snapshot` to see the page)
4. Export cookies to a file:
   ```bash
   mkdir -p ~/.openclaw/cookies
   openclaw browser cookies > ~/.openclaw/cookies/keepa.json
   ```
6. Repeat for each site you need authenticated access to

### Automated Session Restore

To restore cookies in an automated session, use a helper script that reads the saved JSON and sets each cookie:

```bash
# Restore cookies from a saved file
python3 -c "
import json, subprocess
with open('$HOME/.openclaw/cookies/keepa.json') as f:
    cookies = json.load(f)
for c in cookies:
    if 'keepa.com' in c.get('domain', ''):
        subprocess.run([
            'openclaw', 'browser', 'cookies', 'set',
            c['name'], c['value'],
            '--url', f\"https://{c['domain'].lstrip('.')}{c.get('path', '/')}\"
        ])
"
```

Then verify the session:
```bash
openclaw browser navigate "https://keepa.com/#!finder"
openclaw browser snapshot  # Check if logged in (no login form visible)
```

### Session Refresh Pattern

```bash
# Check if session is still valid
openclaw browser navigate "https://keepa.com/#!finder"
openclaw browser snapshot
# If login page detected → re-import cookies or re-authenticate manually
# If finder page loads with data → session is valid, proceed
```

## Strategy 2: Credential Vault

Encrypted credential storage for automated login flows.

### Store Credentials

```bash
openclaw vault set keepa.username "<username>"
openclaw vault set keepa.password "<password>"
```

### Retrieve Credentials

```bash
USERNAME=$(openclaw vault get keepa.username)
PASSWORD=$(openclaw vault get keepa.password)
```

### Vault Security

- Stored in `~/.openclaw/credentials/` with 700 permissions
- Encrypted with machine-local key
- Never logged, never committed, never sent to Discord
- Access logged in audit trail

## Strategy 3: Automated Login Flow

For sites that require fresh login (e.g., session cookies expire quickly).

### Pattern

1. Navigate to login page:
   ```bash
   openclaw browser navigate "https://keepa.com/signin"
   ```
2. Snapshot to identify form fields:
   ```bash
   openclaw browser snapshot
   ```
3. Type credentials from vault:
   ```bash
   openclaw browser type <username-ref> "$(openclaw vault get keepa.username)"
   openclaw browser type <password-ref> "$(openclaw vault get keepa.password)"
   ```
4. Submit form:
   ```bash
   openclaw browser click <submit-ref>
   ```
5. Verify login success:
   ```bash
   openclaw browser snapshot
   ```
6. Export fresh cookies:
   ```bash
   openclaw browser cookies > ~/.openclaw/cookies/keepa.json
   ```

## Browser Access

OpenClaw uses its built-in managed browser (`openclaw` profile).

```bash
openclaw browser --browser-profile openclaw status   # Check managed browser
openclaw browser --browser-profile openclaw start    # Start managed browser
openclaw browser --browser-profile openclaw snapshot # Screenshot current page
```

## Safety Rules

- **NEVER** log credentials to any file (audit logs, Discord, context files)
- **NEVER** commit cookie files or credential files to git
- **NEVER** send credentials via Discord messages
- **ONLY** access credentials via `openclaw vault get`
- **ALWAYS** verify session validity before proceeding with authenticated work
- **ALWAYS** use cookie import as the first strategy (avoids typing credentials)

## Supported Sites

| Site | Auth Strategy | Cookie Domain | Session Lifetime | Notes |
|------|--------------|---------------|-----------------|-------|
| Keepa | Cookie import | `.keepa.com` | ~24h | Cloudflare protected |
| Amazon Seller Central | Cookie import | `.amazon.com` | Varies | May require 2FA on fresh login |
