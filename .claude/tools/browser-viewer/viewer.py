#!/usr/bin/env python3
"""CDP Screencast Viewer — live browser stream via WebSocket.

Connects to OpenClaw's managed browser CDP endpoint, captures frames with
Page.startScreencast, and pushes them to any connected web client.
"""

import asyncio
import json
import os
from pathlib import Path

import aiohttp
from aiohttp import web
import websockets

CDP_HOST = os.environ.get("CDP_HOST", "host.docker.internal")
CDP_PORT = int(os.environ.get("CDP_PORT", "9222"))
VIEWER_PORT = int(os.environ.get("VIEWER_PORT", "6080"))
QUALITY = int(os.environ.get("QUALITY", "80"))

clients: set[web.WebSocketResponse] = set()
current_frame: str | None = None


async def get_ws_url() -> str | None:
    """Get WebSocket debugger URL for the first page target."""
    url = f"http://{CDP_HOST}:{CDP_PORT}/json"
    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(url, timeout=aiohttp.ClientTimeout(total=5)) as resp:
                targets = await resp.json()
                for t in targets:
                    if t.get("type") == "page":
                        ws_url = t["webSocketDebuggerUrl"]
                        # Rewrite localhost references to the configured CDP_HOST
                        # so Docker containers can reach the host browser.
                        ws_url = ws_url.replace("localhost", CDP_HOST)
                        ws_url = ws_url.replace("127.0.0.1", CDP_HOST)
                        return ws_url
    except Exception:
        return None
    return None


async def screencast_loop() -> None:
    """Connect to CDP and stream screencast frames forever."""
    global current_frame
    msg_id = 0

    while True:
        try:
            ws_url = await get_ws_url()
            if not ws_url:
                await asyncio.sleep(2)
                continue

            async with websockets.connect(ws_url, max_size=50 * 1024 * 1024) as ws:
                # Enable Page domain
                msg_id += 1
                await ws.send(json.dumps({"id": msg_id, "method": "Page.enable"}))
                await ws.recv()

                # Start screencast
                msg_id += 1
                await ws.send(json.dumps({
                    "id": msg_id,
                    "method": "Page.startScreencast",
                    "params": {
                        "format": "jpeg",
                        "quality": QUALITY,
                        "maxWidth": 1920,
                        "maxHeight": 1080,
                        "everyNthFrame": 1,
                    },
                }))

                async for raw in ws:
                    data = json.loads(raw)
                    if data.get("method") != "Page.screencastFrame":
                        continue

                    params = data["params"]
                    current_frame = params["data"]  # base64 JPEG
                    session_id = params["sessionId"]

                    # Acknowledge so Chrome sends the next frame
                    msg_id += 1
                    await ws.send(json.dumps({
                        "id": msg_id,
                        "method": "Page.screencastFrameAck",
                        "params": {"sessionId": session_id},
                    }))

                    # Broadcast to all viewer clients
                    if clients:
                        frame_msg = json.dumps({"frame": current_frame})
                        await asyncio.gather(
                            *(c.send_str(frame_msg) for c in clients),
                            return_exceptions=True,
                        )

        except Exception as exc:
            print(f"[viewer] CDP error: {exc}, reconnecting in 3s...")
            await asyncio.sleep(3)


# ── HTTP handlers ────────────────────────────────────────────

async def websocket_handler(request: web.Request) -> web.WebSocketResponse:
    ws = web.WebSocketResponse()
    await ws.prepare(request)
    clients.add(ws)

    # Send the last captured frame immediately
    if current_frame:
        await ws.send_str(json.dumps({"frame": current_frame}))

    try:
        async for _msg in ws:
            pass  # viewer clients are receive-only
    finally:
        clients.discard(ws)
    return ws


async def index_handler(_request: web.Request) -> web.FileResponse:
    return web.FileResponse(Path(__file__).parent / "index.html")


async def health_handler(_request: web.Request) -> web.Response:
    return web.json_response({
        "status": "ok",
        "clients": len(clients),
        "has_frame": current_frame is not None,
    })


# ── App lifecycle ────────────────────────────────────────────

async def on_startup(app: web.Application) -> None:
    app["screencast_task"] = asyncio.create_task(screencast_loop())


async def on_cleanup(app: web.Application) -> None:
    app["screencast_task"].cancel()
    try:
        await app["screencast_task"]
    except asyncio.CancelledError:
        pass


def main() -> None:
    app = web.Application()
    app.router.add_get("/", index_handler)
    app.router.add_get("/ws", websocket_handler)
    app.router.add_get("/health", health_handler)
    app.on_startup.append(on_startup)
    app.on_cleanup.append(on_cleanup)

    print(f"[viewer] Live browser viewer on http://0.0.0.0:{VIEWER_PORT}")
    print(f"[viewer] CDP target: {CDP_HOST}:{CDP_PORT}")
    web.run_app(app, host="0.0.0.0", port=VIEWER_PORT, print=None)


if __name__ == "__main__":
    main()
