/**
 * Bridge /think <level> from Discord/OpenClaw to claude-max-proxy's admin endpoint.
 *
 * OpenClaw's /think only affects its own thinkingDefault and is not forwarded to
 * OpenAI-compatible providers. This hook watches inbound messages, detects the
 * /think directive, and pushes the same level to the proxy's runtime config so
 * extended thinking stays in sync.
 */

const ALLOWED_LEVELS = new Set([
  "off",
  "low",
  "medium",
  "high",
  "xhigh",
  "max",
]);

// The proxy container is reachable by name on the shared Docker network.
// Override with CLAUDE_MAX_PROXY_URL for non-default setups.
const PROXY_URL =
  process.env.CLAUDE_MAX_PROXY_URL ||
  "http://claude-max-proxy:3456/admin/thinking-budget";

interface HookEvent {
  type: string;
  context?: {
    content?: string;
  };
}

const THINK_RE = /(?:^|\s)\/(?:t|think|thinking)[:\s]+([a-z]+)/i;

const handler = async (event: HookEvent): Promise<void> => {
  if (event.type !== "message:received") return;
  const content = event.context?.content;
  if (!content) return;

  const match = THINK_RE.exec(content);
  if (!match) return;
  const level = match[1].toLowerCase();
  if (!ALLOWED_LEVELS.has(level)) return;

  try {
    const response = await fetch(PROXY_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ budget: level }),
    });
    if (!response.ok) {
      const body = await response.text();
      console.error(
        "[claude-max-proxy-think] proxy status " +
          response.status +
          ": " +
          body,
      );
    }
  } catch (err) {
    console.error("[claude-max-proxy-think] proxy update failed:", err);
  }
};

export default handler;
