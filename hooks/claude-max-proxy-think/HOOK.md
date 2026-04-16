---
name: claude-max-proxy-think
description: Bridge OpenClaw's /think command to claude-max-proxy's admin endpoint so Discord /think changes the proxy's thinking budget live.
metadata: { "openclaw": { "emoji": "🧠", "events": ["message:received"] } }
---

# claude-max-proxy-think

Parses `/think <level>` from inbound Discord messages and updates the
claude-max-proxy default thinking budget via its admin endpoint.

OpenClaw does not forward `thinkingDefault` to OpenAI-compatible providers,
so the proxy defaults to no extended thinking. This hook closes that gap —
every `/think <level>` in Discord also updates the proxy.

Accepted levels map to Claude CLI effort: `off | low | medium | high | xhigh | max`.
The hook silently ignores unknown levels (OpenClaw handles its own validation).
