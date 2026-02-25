#!/usr/bin/env python3
"""CDP Screencast Viewer — live interactive browser stream via WebSocket.

Connects to OpenClaw's managed browser CDP endpoint, captures frames with
Page.startScreencast, and pushes them to any connected web client.

Also accepts mouse/keyboard input from viewer clients and forwards them
to Chrome via CDP Input.dispatch* methods, enabling interactive control
(e.g. logging into Keepa, Amazon Seller Central before OpenClaw takes over).

Includes a reverse proxy for Chrome DevTools access at /devtools/.
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
# Shared reference to the active CDP websocket for input forwarding
cdp_ws: websockets.WebSocketClientProtocol | None = None
cdp_msg_id: int = 0
cdp_lock = asyncio.Lock()

# Track screencast metadata for coordinate translation
screencast_meta: dict = {"offsetTop": 0, "pageScaleFactor": 1, "scrollOffsetX": 0, "scrollOffsetY": 0}


async def cdp_send(method: str, params: dict | None = None) -> None:
    """Send a CDP command through the shared connection."""
    global cdp_msg_id
    if cdp_ws is None:
        return
    async with cdp_lock:
        cdp_msg_id += 1
        msg = {"id": cdp_msg_id, "method": method}
        if params:
            msg["params"] = params
        try:
            await cdp_ws.send(json.dumps(msg))
        except Exception:
            pass


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
                        ws_url = ws_url.replace("localhost", CDP_HOST)
                        ws_url = ws_url.replace("127.0.0.1", CDP_HOST)
                        return ws_url
    except Exception:
        return None
    return None


async def screencast_loop() -> None:
    """Connect to CDP and stream screencast frames forever."""
    global current_frame, cdp_ws

    while True:
        try:
            ws_url = await get_ws_url()
            if not ws_url:
                await asyncio.sleep(2)
                continue

            async with websockets.connect(ws_url, max_size=50 * 1024 * 1024) as ws:
                cdp_ws = ws

                # Enable Page and Input domains
                await cdp_send("Page.enable")
                await ws.recv()
                await cdp_send("Input.enable")
                # Consume any response (Input.enable may not return one on all versions)
                try:
                    await asyncio.wait_for(ws.recv(), timeout=1)
                except asyncio.TimeoutError:
                    pass

                # Start screencast
                await cdp_send("Page.startScreencast", {
                    "format": "jpeg",
                    "quality": QUALITY,
                    "maxWidth": 1920,
                    "maxHeight": 1080,
                    "everyNthFrame": 1,
                })

                async for raw in ws:
                    data = json.loads(raw)
                    if data.get("method") != "Page.screencastFrame":
                        continue

                    params = data["params"]
                    current_frame = params["data"]  # base64 JPEG
                    session_id = params["sessionId"]
                    meta = params.get("metadata", {})
                    screencast_meta.update({
                        "offsetTop": meta.get("offsetTop", 0),
                        "pageScaleFactor": meta.get("pageScaleFactor", 1),
                        "scrollOffsetX": meta.get("scrollOffsetX", 0),
                        "scrollOffsetY": meta.get("scrollOffsetY", 0),
                        "deviceWidth": meta.get("deviceWidth", 1920),
                        "deviceHeight": meta.get("deviceHeight", 1080),
                    })

                    # Acknowledge so Chrome sends the next frame
                    await cdp_send("Page.screencastFrameAck", {"sessionId": session_id})

                    # Broadcast frame + metadata to all viewer clients
                    if clients:
                        frame_msg = json.dumps({
                            "frame": current_frame,
                            "meta": screencast_meta,
                        })
                        await asyncio.gather(
                            *(c.send_str(frame_msg) for c in clients),
                            return_exceptions=True,
                        )

        except Exception as exc:
            print(f"[viewer] CDP error: {exc}, reconnecting in 3s...")
            cdp_ws = None
            await asyncio.sleep(3)


async def handle_input(data: dict) -> None:
    """Forward a viewer input event to Chrome via CDP."""
    evt = data.get("type")
    if not evt:
        return

    if evt in ("mousePressed", "mouseReleased", "mouseMoved"):
        params: dict = {
            "type": evt,
            "x": data.get("x", 0),
            "y": data.get("y", 0),
            "button": data.get("button", "left"),
            "clickCount": data.get("clickCount", 1),
            "modifiers": data.get("modifiers", 0),
        }
        if evt == "mousePressed":
            params["clickCount"] = data.get("clickCount", 1)
        await cdp_send("Input.dispatchMouseEvent", params)

    elif evt == "mouseWheel":
        await cdp_send("Input.dispatchMouseEvent", {
            "type": "mouseWheel",
            "x": data.get("x", 0),
            "y": data.get("y", 0),
            "deltaX": data.get("deltaX", 0),
            "deltaY": data.get("deltaY", 0),
            "modifiers": data.get("modifiers", 0),
        })

    elif evt in ("keyDown", "keyUp"):
        params = {
            "type": evt,
            "modifiers": data.get("modifiers", 0),
        }
        if data.get("key"):
            params["key"] = data["key"]
        if data.get("code"):
            params["code"] = data["code"]
        if data.get("text"):
            params["text"] = data["text"]
        if data.get("unmodifiedText"):
            params["unmodifiedText"] = data["unmodifiedText"]
        if data.get("windowsVirtualKeyCode"):
            params["windowsVirtualKeyCode"] = data["windowsVirtualKeyCode"]
            params["nativeVirtualKeyCode"] = data["windowsVirtualKeyCode"]
        await cdp_send("Input.dispatchKeyEvent", params)

    elif evt == "char":
        await cdp_send("Input.dispatchKeyEvent", {
            "type": "char",
            "text": data.get("text", ""),
            "unmodifiedText": data.get("text", ""),
            "modifiers": data.get("modifiers", 0),
        })

    elif evt == "navigate":
        url = data.get("url", "")
        if url:
            await cdp_send("Page.navigate", {"url": url})


# ── HTTP handlers ────────────────────────────────────────────

async def websocket_handler(request: web.Request) -> web.WebSocketResponse:
    ws = web.WebSocketResponse()
    await ws.prepare(request)
    clients.add(ws)

    # Send the last captured frame immediately
    if current_frame:
        await ws.send_str(json.dumps({"frame": current_frame, "meta": screencast_meta}))

    try:
        async for msg in ws:
            if msg.type == aiohttp.WSMsgType.TEXT:
                try:
                    data = json.loads(msg.data)
                    if data.get("input"):
                        await handle_input(data["input"])
                except (json.JSONDecodeError, KeyError):
                    pass
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
        "cdp_connected": cdp_ws is not None,
    })


async def cdp_proxy_handler(request: web.Request) -> web.Response:
    """Reverse proxy for Chrome DevTools Protocol HTTP endpoints."""
    path = request.match_info.get("path", "")
    target_url = f"http://{CDP_HOST}:{CDP_PORT}/{path}"
    
    async with aiohttp.ClientSession() as session:
        try:
            async with session.request(
                method=request.method,
                url=target_url,
                headers={k: v for k, v in request.headers.items() if k.lower() not in ("host", "connection")},
                data=await request.read() if request.can_read_body else None,
                timeout=aiohttp.ClientTimeout(total=30),
            ) as resp:
                # Forward response
                headers = {k: v for k, v in resp.headers.items() if k.lower() not in ("transfer-encoding", "connection")}
                return web.Response(
                    status=resp.status,
                    headers=headers,
                    body=await resp.read(),
                )
        except Exception as e:
            return web.Response(status=502, text=f"CDP proxy error: {e}")


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
    # Proxy Chrome DevTools endpoints
    app.router.add_route("*", "/devtools/{path:.*}", cdp_proxy_handler)
    app.on_startup.append(on_startup)
    app.on_cleanup.append(on_cleanup)

    print(f"[viewer] Interactive browser viewer on http://0.0.0.0:{VIEWER_PORT}")
    print(f"[viewer] CDP target: {CDP_HOST}:{CDP_PORT}")
    print(f"[viewer] DevTools proxy: http://0.0.0.0:{VIEWER_PORT}/devtools/")
    web.run_app(app, host="0.0.0.0", port=VIEWER_PORT, print=None)


if __name__ == "__main__":
    main()
