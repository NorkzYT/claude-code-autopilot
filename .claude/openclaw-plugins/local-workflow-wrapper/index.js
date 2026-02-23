import fs from "node:fs";
import path from "node:path";
import { spawn } from "node:child_process";

function asArray(value) {
  return Array.isArray(value) ? value : [];
}

function asRecord(value) {
  return value && typeof value === "object" && !Array.isArray(value) ? value : {};
}

function get(obj, p) {
  return p.split(".").reduce((acc, part) => (acc && typeof acc === "object" ? acc[part] : undefined), obj);
}

function uniq(values) {
  return [...new Set(values.filter((v) => !!v && typeof v === "string"))];
}

function trimOut(s, max = 3000) {
  if (!s) return "";
  return s.length > max ? `${s.slice(0, max - 80)}\n...[truncated]` : s;
}

function parseArgs(ctx) {
  if (Array.isArray(ctx?.args)) return ctx.args.map(String).filter(Boolean);
  if (typeof ctx?.commandBody === "string" && ctx.commandBody.trim()) {
    return ctx.commandBody.trim().split(/\s+/);
  }
  return [];
}

function configuredAgents(config) {
  const agents = asRecord(config?.agents);
  const list = asArray(agents.list);
  return list
    .map((a) => asRecord(a))
    .filter((a) => typeof a.id === "string" || typeof a.name === "string")
    .map((a) => ({
      id: String(a.id || a.name),
      name: typeof a.name === "string" ? a.name : undefined,
      workspace: typeof a.workspace === "string" ? a.workspace : undefined,
    }));
}

function findWorkspaceForAgent(config, agentId) {
  const agents = configuredAgents(config);
  const match = agents.find((a) => a.id === agentId || a.name === agentId);
  return match?.workspace || null;
}

function extractAgentFromSessionKey(ctx) {
  const candidates = uniq([
    get(ctx, "sessionKey"),
    get(ctx, "session.key"),
    get(ctx, "session.id"),
    get(ctx, "sessionId"),
  ]);
  for (const value of candidates) {
    const m = value.match(/agent:([^:]+):/);
    if (m) return m[1];
  }
  return null;
}

function resolveBoundAgentId(config, ctx) {
  const bindings = asArray(config?.bindings).map((b) => asRecord(b));
  if (!bindings.length) return null;

  const transport = typeof ctx?.channel === "string" ? ctx.channel : undefined;
  const guildIds = uniq([
    get(ctx, "guildId"),
    get(ctx, "discord.guildId"),
    get(ctx, "message.guildId"),
    get(ctx, "event.guildId"),
    get(ctx, "raw.guildId"),
  ]);
  const peerIds = uniq([
    get(ctx, "peerId"),
    get(ctx, "channelId"),
    get(ctx, "peer.id"),
    get(ctx, "discord.channelId"),
    get(ctx, "message.channelId"),
    get(ctx, "event.channelId"),
    get(ctx, "raw.channelId"),
  ]);

  for (const binding of bindings) {
    const match = asRecord(binding.match);
    const peer = asRecord(match.peer);
    if (transport && typeof match.channel === "string" && match.channel !== transport) continue;
    if (typeof match.guildId === "string" && !guildIds.includes(match.guildId)) continue;
    if (typeof peer.id === "string" && !peerIds.includes(peer.id)) continue;
    if (typeof binding.agentId === "string") return binding.agentId;
  }
  return null;
}

function resolveWorkspaceAndAgent(config, ctx, args) {
  let explicitAgent = null;
  let explicitRepo = null;

  for (let i = 0; i < args.length; i += 1) {
    const a = args[i];
    if ((a === "--repo" || a === "-r") && args[i + 1]) {
      explicitRepo = args[i + 1];
      i += 1;
      continue;
    }
    if ((a === "--agent" || a === "-a") && args[i + 1]) {
      explicitAgent = args[i + 1];
      i += 1;
      continue;
    }
    if (!a.startsWith("-")) {
      if (a.includes("/") || a.startsWith(".")) explicitRepo = a;
      else explicitAgent = a;
    }
  }

  if (explicitRepo) {
    const repo = path.resolve(explicitRepo);
    return { workspace: repo, agentId: explicitAgent || null, source: "arg:repo" };
  }

  if (explicitAgent) {
    const ws = findWorkspaceForAgent(config, explicitAgent);
    if (ws) return { workspace: ws, agentId: explicitAgent, source: "arg:agent" };
    return { error: `Unknown agent: ${explicitAgent}` };
  }

  const sessionAgent = extractAgentFromSessionKey(ctx);
  if (sessionAgent) {
    const ws = findWorkspaceForAgent(config, sessionAgent);
    if (ws) return { workspace: ws, agentId: sessionAgent, source: "session" };
  }

  const boundAgent = resolveBoundAgentId(config, ctx);
  if (boundAgent) {
    const ws = findWorkspaceForAgent(config, boundAgent);
    if (ws) return { workspace: ws, agentId: boundAgent, source: "binding" };
  }

  const nonMain = configuredAgents(config).filter((a) => a.id !== "main" && a.workspace);
  if (nonMain.length === 1) {
    return { workspace: nonMain[0].workspace, agentId: nonMain[0].id, source: "single-agent-fallback" };
  }

  return {
    error:
      "Could not resolve repo workspace. Use /localflow --agent <agent-id> or /localflow --repo /path/to/repo",
  };
}

function reportPath(workspace) {
  return path.join(workspace, ".openclaw", "workflow-report.local.json");
}

function loadReport(workspace) {
  const p = reportPath(workspace);
  if (!fs.existsSync(p)) return null;
  try {
    return JSON.parse(fs.readFileSync(p, "utf8"));
  } catch {
    return null;
  }
}

function summarizeReport(workspace, agentId, report) {
  if (!report || typeof report !== "object") {
    return `No workflow report found at \`${reportPath(workspace)}\`. Run \`/localflow\` first.`;
  }
  const steps = asRecord(report.steps);
  const build = steps.build ?? "unknown";
  const runLocal = steps.run_local ?? "unknown";
  const test = steps.test ?? "unknown";
  const confirm = steps.confirm ?? "unknown";
  const statuses = [build, runLocal, test, confirm].map(String);
  const ok = statuses.every((s) => s === "passed");
  const header = ok ? "Local workflow report: PASS" : "Local workflow report: CHECK";
  const agentLine = agentId ? `Agent: \`${agentId}\`\n` : "";
  return [
    header,
    agentLine + `Repo: \`${workspace}\``,
    `- build: ${build}`,
    `- run-local: ${runLocal}`,
    `- test: ${test}`,
    `- confirm: ${confirm}`,
    `Report: \`${reportPath(workspace)}\``,
  ].join("\n");
}

function runShell(workspace, scriptPath) {
  return new Promise((resolve) => {
    const child = spawn("bash", [scriptPath, "--repo", workspace], {
      cwd: workspace,
      env: process.env,
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    child.stdout.on("data", (d) => {
      stdout += String(d);
    });
    child.stderr.on("data", (d) => {
      stderr += String(d);
    });
    child.on("close", (code) => resolve({ code: code ?? 1, stdout, stderr }));
    child.on("error", (e) => resolve({ code: 1, stdout, stderr: `${stderr}\n${String(e)}` }));
  });
}

export async function register(api) {
  const log = api?.logger ?? console;

  api.registerCommand(
    "/workflowcheck",
    async (ctx) => {
      const config = ctx?.config || {};
      const resolved = resolveWorkspaceAndAgent(config, ctx, parseArgs(ctx));
      if ("error" in resolved) return `⚠️ ${resolved.error}`;
      return summarizeReport(resolved.workspace, resolved.agentId, loadReport(resolved.workspace));
    },
    {
      description: "Check the local workflow report (build/run-local/test/confirm)",
      argsHint: "[--agent <id> | --repo <path>]",
    },
  );

  api.registerCommand(
    "/localflow",
    async (ctx) => {
      const config = ctx?.config || {};
      const resolved = resolveWorkspaceAndAgent(config, ctx, parseArgs(ctx));
      if ("error" in resolved) return `⚠️ ${resolved.error}`;

      const workspace = resolved.workspace;
      const wrapper = path.join(workspace, ".claude", "scripts", "openclaw-local-workflow.sh");
      if (!fs.existsSync(wrapper)) {
        return `⚠️ Local workflow wrapper not found: \`${wrapper}\``;
      }

      const result = await runShell(workspace, wrapper);
      const report = loadReport(workspace);
      const summary = summarizeReport(workspace, resolved.agentId, report);

      const details = [
        `Wrapper exit code: ${result.code}`,
        result.stderr ? `stderr:\n${trimOut(result.stderr, 1200)}` : "",
        result.stdout ? `stdout:\n${trimOut(result.stdout, 1200)}` : "",
      ]
        .filter(Boolean)
        .join("\n\n");

      return `${summary}\n\n${details}`;
    },
    {
      description: "Run the repo-local engineering workflow wrapper",
      argsHint: "[--agent <id> | --repo <path>]",
    },
  );

  api.registerHook(
    "command:new",
    async (ctx) => {
      try {
        const resolved = resolveWorkspaceAndAgent(ctx?.config || {}, ctx, []);
        if ("error" in resolved) return { ok: true };
        const p = reportPath(resolved.workspace);
        if (fs.existsSync(p)) {
          fs.rmSync(p, { force: true });
          log?.debug?.("local-workflow-wrapper cleared stale workflow report on /new", {
            workspace: resolved.workspace,
            report: p,
          });
        }
      } catch (e) {
        log?.warn?.("local-workflow-wrapper hook error", { error: String(e) });
      }
      return { ok: true };
    },
    {
      id: "local-workflow-wrapper.command-new",
      description: "Clear stale local workflow reports when a new session starts",
    },
  );
}

export default register;
