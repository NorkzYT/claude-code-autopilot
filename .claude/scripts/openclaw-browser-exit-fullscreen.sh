#!/usr/bin/env bash
# Set OpenClaw browser window to normal 1920x1080 (not fullscreen/minimized/maximized)
# Usage: bash openclaw-browser-exit-fullscreen.sh [cdp-port]

set -euo pipefail

CDP_PORT="${1:-18800}"

python3 << 'EOF'
import json
import sys
import urllib.request

CDP_PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 18800

req = urllib.request.Request(f'http://127.0.0.1:{CDP_PORT}/json')
try:
    with urllib.request.urlopen(req, timeout=5) as resp:
        targets = json.loads(resp.read())
        for t in targets:
            if t.get("type") == "page":
                ws_url = t["webSocketDebuggerUrl"]

                import websockets
                import asyncio

                async def set_window_bounds():
                    async with websockets.connect(ws_url) as ws:
                        # Get current window
                        await ws.send(json.dumps({"id": 1, "method": "Browser.getWindowForTarget"}))
                        resp = json.loads(await ws.recv())
                        
                        if "result" in resp:
                            window_id = resp["result"]["windowId"]
                            
                            # Set to normal 1920x1080
                            await ws.send(json.dumps({
                                "id": 2,
                                "method": "Browser.setWindowBounds",
                                "params": {
                                    "windowId": window_id,
                                    "bounds": {
                                        "left": 0,
                                        "top": 0,
                                        "width": 1920,
                                        "height": 1080,
                                        "windowState": "normal"
                                    }
                                }
                            }))
                            await ws.recv()

                asyncio.run(set_window_bounds())
                print(f"Set browser window to 1920x1080 normal mode")
                break
except Exception as e:
    print(f"Failed to set window bounds: {e}", file=sys.stderr)
    sys.exit(1)
EOF
