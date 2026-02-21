# Chrome Extension Testing via Extension Relay

> How to test Chrome extensions using OpenClaw's Extension Relay mode.

## Why Extension Relay?

Chrome DevTools Protocol (CDP) cannot dynamically load extensions in headless mode. Extension Relay attaches to a real Chrome instance where extensions are already installed, giving OpenClaw full control over extension-injected UI.

## Setup

### 1. Create Dedicated Chrome Profile

Create a separate Chrome profile for OpenClaw automation (never use your daily driver):

```bash
google-chrome --user-data-dir="$HOME/.openclaw/chrome-profiles/extension-testing" --no-first-run
```

### 2. Install Target Extensions

In the dedicated profile, install:
- Keepa (product price tracker)
- Custom scraper extensions
- Any other extensions you want to test

### 3. Install OpenClaw Browser Relay Extension

1. Install from Chrome Web Store: search "OpenClaw Browser Relay"
2. Configure relay: Settings → Gateway URL `ws://127.0.0.1:18789`
3. Toggle relay icon on the tab you want to control

### 4. Configure OpenClaw Profile

Add to OpenClaw config:

```json
{
  "defaultProfile": "extension-testing",
  "profiles": {
    "extension-testing": {
      "driver": "extension",
      "cdpUrl": "http://127.0.0.1:18792"
    }
  }
}
```

## Testing Workflow

### Basic Extension Interaction

```bash
# 1. Snapshot page including extension-injected elements
openclaw browser snapshot --interactive

# 2. Click extension buttons/UI elements
openclaw browser click <ref>

# 3. Verify result after interaction
openclaw browser snapshot

# 4. Capture evidence screenshot
openclaw browser screenshot --name "extension-test-<name>"
```

### Keepa Product Finder Example

```bash
# Navigate to product page (e.g., Amazon)
openclaw browser navigate "https://www.amazon.com/dp/B0..."

# Wait for Keepa extension to inject its UI
# (Keepa adds price history chart below the product)
sleep 3

# Snapshot to see Keepa-injected elements
openclaw browser snapshot --interactive

# Click Keepa's "Track Product" button (ref from snapshot)
openclaw browser click <keepa-track-ref>

# Verify tracking was added
openclaw browser snapshot
openclaw browser screenshot --name "keepa-tracking-confirmed"
```

### Custom Extension + External Site (e.g., Kairo)

```bash
# Load page with extension content script active
openclaw browser navigate <product-page-url>

# Snapshot to find extension-injected scrape button
openclaw browser snapshot --interactive

# Click extension's "Export to Kairo" button
openclaw browser click <export-ref>

# Verify data flowed to target site
openclaw browser navigate <kairo-dashboard-url>
openclaw browser snapshot
openclaw browser screenshot --name "kairo-export-verified"
```

### Extension Popup Testing

```bash
# Note: Extension popups from toolbar are harder to access
# Prefer testing content-script-injected elements instead

# For extension pages (options, popups opened as tabs):
openclaw browser navigate "chrome-extension://<extension-id>/popup.html"
openclaw browser snapshot --interactive
```

## Limitations

- **Must use headed mode** — Extensions don't load in headless Chrome
- **Element refs are stale after navigation** — Always re-snapshot after page changes
- **Extension popups** from the toolbar are less accessible than content-script-injected elements
- **Some extensions detect automation** — May need to set `navigator.webdriver = false`
- **Cross-origin restrictions** — Extension relay respects Chrome's security model

## Configuration Reference

```bash
# Enable headed mode for extension testing
openclaw config set browser.headless false

# Set extension testing profile as default
openclaw config set browser.defaultProfile "extension-testing"

# Verify relay connection
openclaw browser relay status
```
