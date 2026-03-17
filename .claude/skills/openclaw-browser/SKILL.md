# OpenClaw Browser Automation Skill

> Visual testing, E2E automation, and web research using OpenClaw's managed browser.

## Prerequisites

- OpenClaw installed and configured
- Browser feature enabled in `~/.openclaw/openclaw.json`: `"browser": {"enabled": true}`
- Chromium/Chrome available (OpenClaw auto-manages via CDP)

## Docker Host Access

When OpenClaw runs in Docker, host-local services are not available at `localhost` from inside the browser container context.

- If the human says `http://localhost:<port>` for a host dev server, translate it to `http://host.docker.internal:<port>` before navigating.
- Example: host app at `http://localhost:8080` should be opened as `http://host.docker.internal:8080` from OpenClaw.
- Only keep `localhost` unchanged when the service is actually running inside the same container namespace.

## Capabilities

### Visual Regression Testing

Compare before/after screenshots to detect visual changes:

1. **Capture baseline**: Take screenshot of current state
   ```
   openclaw browser navigate <url>
   openclaw browser screenshot --name "baseline"
   ```

2. **Make code changes**: Implement the feature or fix

3. **Capture comparison**: Take screenshot after changes
   ```
   openclaw browser screenshot --name "after-change"
   ```

4. **Compare**: Analyze differences
   ```
   openclaw browser compare "baseline" "after-change"
   ```

### E2E Test Automation

Use AI-powered element identification (numeric refs) for stable selectors:

```
openclaw browser navigate <url>
openclaw browser snapshot  # Returns numbered element refs
openclaw browser click 5   # Click element #5
openclaw browser type 3 "test@example.com"  # Type into element #3
openclaw browser screenshot --name "after-interaction"
```

### Web Research

Fetch and analyze web pages for documentation or research:

```
openclaw browser navigate "https://docs.example.com/api"
openclaw browser extract-text  # Get page text content
```

### Live Frontend Preview

For projects with a dev server:

```
# Start dev server (if not running)
exec npm run dev &

# Navigate and analyze
openclaw browser navigate "http://host.docker.internal:3000"
openclaw browser screenshot --name "preview"
openclaw browser analyze  # Vision model analyzes the UI
```

### Discord Integration

Send screenshots directly to Discord:

```
openclaw browser screenshot --name "ui-state" --announce
```

This captures the screenshot and posts it to the configured Discord channel.

## Vision Model Analysis

Screenshots can be analyzed by the vision model (Sonnet 4.5) for:
- Layout issues (overlapping elements, broken alignment)
- Missing content (empty states, placeholder text still visible)
- Accessibility concerns (contrast, font sizes)
- Mobile responsiveness (when tested at different viewports)

```
openclaw browser analyze --viewport "mobile"  # 375x812
openclaw browser analyze --viewport "tablet"  # 768x1024
openclaw browser analyze --viewport "desktop" # 1920x1080
```

## Safety Notes

- Browser runs in headless mode by default
- No access to local filesystem from browser context
- Network requests are sandboxed to the browser process
- Screenshots are stored in OpenClaw's workspace (not committed to git)
