#!/usr/bin/env bash
# Exit fullscreen mode in OpenClaw browser via CDP
# Usage: bash openclaw-browser-exit-fullscreen.sh [cdp-port]

set -euo pipefail

CDP_PORT="${1:-18800}"

python3 << 'EOF'
import json
import sys
import urllib.request

CDP_PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 18800

# Get the first page target
req = urllib.request.Request(f'http://127.0.0.1:{CDP_PORT}/json')
try:
    with urllib.request.urlopen(req, timeout=5) as resp:
        targets = json.loads(resp.read())
        for t in targets:
            if t.get("type") == "page":
                ws_url = t["webSocketDebuggerUrl"]

                # Send F11 key via CDP to exit fullscreen
                import websockets
                import asyncio

                async def send_f11():
                    async with websockets.connect(ws_url) as ws:
                        await ws.send(json.dumps({"id": 1, "method": "Input.enable"}))
                        await ws.recv()

                        # F11 keydown
                        await ws.send(json.dumps({
                            "id": 2,
                            "method": "Input.dispatchKeyEvent",
                            "params": {
                                "type": "keyDown",
                                "key": "F11",
                                "code": "F11",
                                "windowsVirtualKeyCode": 122
                            }
                        }))
                        await ws.recv()

                        # F11 keyup
                        await ws.send(json.dumps({
                            "id": 3,
                            "method": "Input.dispatchKeyEvent",
                            "params": {
                                "type": "keyUp",
                                "key": "F11",
                                "code": "F11",
                                "windowsVirtualKeyCode": 122
                            }
                        }))
                        await ws.recv()

                asyncio.run(send_f11())
                print(f"Exited fullscreen mode on CDP port {CDP_PORT}")
                break
except Exception as e:
    print(f"Failed to exit fullscreen: {e}", file=sys.stderr)
    sys.exit(1)
EOF
