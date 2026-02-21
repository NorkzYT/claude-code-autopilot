# Download Patterns

> Patterns for downloading files and capturing HAR data via OpenClaw browser.

## HAR File Capture

### Start/Stop Capture

```bash
# Start capturing network traffic
openclaw browser har start --output ~/.openclaw/downloads/capture.har

# Navigate through the workflow you want to capture
openclaw browser navigate <url-1>
openclaw browser navigate <url-2>
# ... perform interactions ...

# Stop capture and save
openclaw browser har stop
```

### HAR Analysis

```bash
# Extract API endpoints from HAR file
openclaw browser har analyze ~/.openclaw/downloads/capture.har

# Output: list of endpoints, methods, status codes, auth headers
```

### What to Look For in HAR Files

- API base URLs and endpoint patterns
- Authentication headers (Bearer tokens, API keys, cookies)
- Pagination patterns (offset, cursor, page params)
- Rate limit headers (X-RateLimit-*, Retry-After)
- Request/response content types
- WebSocket connections

## File Downloads

### Download Directory

All downloads go to `~/.openclaw/downloads/` (configurable).

```bash
# Download a file
openclaw browser download <url> --output ~/.openclaw/downloads/<filename>
```

### Safety Constraints

- **Maximum file size:** 100MB per file
- **Allowed extensions:** `.har`, `.json`, `.csv`, `.html`, `.txt`, `.pdf`, `.xml`, `.xlsx`
- **Blocked extensions:** `.exe`, `.sh`, `.bat`, `.msi`, `.dmg`, `.pkg`, `.deb`, `.rpm`
- Downloads are scanned before saving
- Download directory is excluded from git tracking

### Cleanup

```bash
# List downloads
ls ~/.openclaw/downloads/

# Clean up old downloads (older than 7 days)
find ~/.openclaw/downloads/ -mtime +7 -delete
```

## API Reverse Engineering Workflow

1. **Capture:** Start HAR → navigate through target site workflows → stop
2. **Analyze:** Extract endpoints, auth patterns, pagination
3. **Document:** Write findings to `.claude/context/<task>/context.md`
4. **Generate:** Create API client code based on discovered endpoints
5. **Test:** Read-only GET requests against live API to verify
6. **NEVER:** Send POST/PUT/DELETE requests to external APIs without explicit approval
