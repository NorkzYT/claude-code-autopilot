# Chrome Extension Testing with OpenClaw

> How to test Chrome extensions using OpenClaw's Managed Browser with automatic extension loading.

## Overview

OpenClaw's Managed Browser (`openclaw` profile) provides full automated control with Chrome extension support via the `--load-extension` flag. Extensions load automatically and work exactly as if manually installed.

**Key Capabilities**:
- ✅ Full automatic control of ALL tabs
- ✅ Extensions load automatically via `--load-extension`
- ✅ Headless mode supported (some extensions may need headed)
- ✅ CDP protocol for maximum control
- ✅ No manual permission needed

## Setup

### 1. Place Extensions in Snap-Accessible Directory

Extensions must be in a location accessible to snap-confined Chromium:

```bash
# Create extension directory (if not exists)
mkdir -p ~/snap/chromium/common/extensions

# Copy your extension to this directory
cp -r /path/to/your-extension ~/snap/chromium/common/extensions/your-extension-name
```

**Important**: Snap's `home` interface EXCLUDES hidden directories (`~/.anything/`). Always use `~/snap/chromium/common/` for extensions.

### 2. Extension Auto-Loading

The wrapper script (`~/.openclaw/chromium-vnc-wrapper.sh`) automatically loads all extensions from `~/snap/chromium/common/extensions/` on browser startup. No additional configuration needed.

### 3. Verify Extension Loading

Check that extensions are loading:

```bash
# Check browser process for --load-extension flag
ps aux | grep chromium | grep "load-extension"

# Should show: --load-extension=.../extensions/extension-name
```

## Testing Workflow

### Basic Extension Interaction

```bash
# Navigate to a page where extension should activate
openclaw browser navigate "https://example.com"

# Take interactive snapshot (shows extension-injected elements)
openclaw browser snapshot --interactive

# Click extension buttons/UI elements
openclaw browser click <ref>

# Verify result
openclaw browser snapshot
```

### Keepa Product Price Tracker Example

```bash
# Navigate to Amazon product page
openclaw browser navigate "https://www.amazon.com/dp/B07DDJNHFF"

# Wait for Keepa to inject price history chart
sleep 3

# Snapshot shows Keepa chart below product image
openclaw browser snapshot --interactive

# Interact with Keepa elements
openclaw browser click <keepa-ref>
```

### Custom Extension Testing

```bash
# Navigate to target page
openclaw browser navigate "https://www.amazon.com/dp/PRODUCT_ID"

# Extension content script should inject UI elements
sleep 2

# Snapshot to find extension-injected elements
openclaw browser snapshot --interactive

# Interact with extension UI (e.g., click export button)
openclaw browser click <extension-button-ref>

# Verify action completed
openclaw browser snapshot
```

### Multi-Tab Extension Testing

```bash
# Open multiple tabs
openclaw browser navigate "https://example.com"
openclaw browser open "https://google.com"
openclaw browser open "https://github.com"

# List all tabs
openclaw browser tabs

# Switch between tabs and verify extension works in each
openclaw browser focus <tab-id>
openclaw browser snapshot --interactive
```

## Verifying Extension Presence

### Check CDP Targets

Extensions create iframe and service worker targets in CDP. Use Python to check:

```python
import urllib.request
import json

data = urllib.request.urlopen('http://localhost:18800/json').read()
targets = json.loads(data)

# Look for extension iframes and service workers
for target in targets:
    if 'chrome-extension' in target.get('url', ''):
        print(f"{target['type']}: {target['url']}")
```

### Visual Verification via VNC

View the browser directly to see extension icons and injected UI:

- Open VNC viewer at: `http://YOUR_SERVER:6081/vnc.html`
- You should see:
  - Extension icons in Chrome toolbar
  - Extension-injected UI elements on pages
  - Extension popups when icons are clicked

## Common Extension Testing Patterns

### Testing Content Scripts

Content scripts inject into page context:

```bash
openclaw browser navigate "https://target-site.com"
sleep 2  # Wait for content script injection

# Check for injected elements
openclaw browser snapshot --interactive

# Interact with injected elements
openclaw browser click <injected-element-ref>
```

### Testing Background Scripts

Background scripts don't have visible UI but can be verified via CDP:

```python
import urllib.request
import json

data = urllib.request.urlopen('http://localhost:18800/json').read()
targets = json.loads(data)

# Check for service workers
for t in targets:
    if 'service-worker' in t.get('type', '').lower():
        print(f"Service Worker: {t.get('url')}")
```

### Testing Extension Popups

Extension popups (from toolbar icons) can be tested by navigating to them as tabs:

```bash
# Open extension popup as tab
openclaw browser navigate "chrome-extension://EXTENSION_ID/popup.html"

# Interact with popup UI
openclaw browser snapshot --interactive
openclaw browser click <popup-element-ref>
```

## Configuration

### Enable Headed Mode for Visual Debugging

Some extensions require visible browser UI:

```bash
openclaw config set browser.headless false
```

### Verify Configuration

```bash
# Check profile (should be "openclaw")
openclaw config get browser.defaultProfile

# Check headless setting
openclaw config get browser.headless

# Check wrapper script
cat ~/.openclaw/chromium-vnc-wrapper.sh
```

## Troubleshooting

### Extension Not Loading

**Check extension directory**:
```bash
ls -la ~/snap/chromium/common/extensions/
```

**Verify wrapper script**:
```bash
cat ~/.openclaw/chromium-vnc-wrapper.sh | grep load-extension
```

**Check browser process**:
```bash
ps aux | grep chromium | grep "load-extension"
```

### Extension Not Injecting into Page

**Wait for content scripts**:
```bash
# Add delay after navigation
openclaw browser navigate "https://target-site.com"
sleep 3  # Wait for injection
openclaw browser snapshot --interactive
```

**Check console for errors**:
```bash
openclaw browser console
```

### Extension Not Visible in Toolbar

**Use VNC viewer** to visually confirm extension icons:
- Open: `http://YOUR_SERVER:6081/vnc.html`
- Check Chrome toolbar for extension icons

**Verify extension manifest** allows toolbar icon:
```bash
cat ~/snap/chromium/common/extensions/YOUR_EXTENSION/manifest.json | grep action
```

## Limitations

- **Snap confinement**: Extensions must be in snap-accessible paths (`~/snap/chromium/common/`)
- **Headless limitations**: Some extension UI features may require headed mode
- **Extension updates**: Must manually update extension files (no auto-update from Chrome Web Store)
- **Element staleness**: Snapshot refs become invalid after navigation (always re-snapshot)

## Best Practices

1. **Always re-snapshot after navigation** - Element refs are page-specific
2. **Use delays after navigation** - Allow time for extension content scripts to inject
3. **Test in headed mode first** - Easier to debug extension behavior visually
4. **Check CDP targets** - Verify extension workers/iframes are present
5. **Monitor console** - Extension errors appear in browser console

## Additional Resources

- **OpenClaw Browser Docs**: https://docs.openclaw.ai/tools/browser
- **Chrome Extension Manifest**: https://developer.chrome.com/docs/extensions/mv3/manifest/
- **CDP Protocol**: https://chromedevtools.github.io/devtools-protocol/
