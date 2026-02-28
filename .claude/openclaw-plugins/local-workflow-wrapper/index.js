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

function shellQuote(value) {
  const s = String(value ?? "");
  return `'${s.replace(/'/g, `'\"'\"'`)}'`;
}

function parseArgs(ctx) {
  if (Array.isArray(ctx?.args)) return ctx.args.map(String).filter(Boolean);
  if (typeof ctx?.commandBody === "string" && ctx.commandBody.trim()) {
    return ctx.commandBody.trim().split(/\s+/);
  }
  return [];
}

function parseDurationSpec(value) {
  if (!value || typeof value !== "string") return null;
  const v = value.trim().toLowerCase();
  if (!v) return null;
  if (/^\d+\s*(s|m|h|d|w)$/.test(v)) return v.replace(/\s+/g, "");
  if (/^\d+[smhdw]$/.test(v)) return v;
  return null;
}

function channelRouting(ctx) {
  const channel = typeof ctx?.channel === "string" ? ctx.channel : null;
  const channelId = uniq([
    get(ctx, "channelId"),
    get(ctx, "peerId"),
    get(ctx, "discord.channelId"),
    get(ctx, "message.channelId"),
    get(ctx, "event.channelId"),
    get(ctx, "raw.channelId"),
  ])[0];
  const userId = uniq([
    get(ctx, "userId"),
    get(ctx, "authorId"),
    get(ctx, "discord.userId"),
    get(ctx, "message.authorId"),
    get(ctx, "event.userId"),
    get(ctx, "raw.userId"),
  ])[0];
  const guildId = uniq([
    get(ctx, "guildId"),
    get(ctx, "discord.guildId"),
    get(ctx, "message.guildId"),
    get(ctx, "event.guildId"),
    get(ctx, "raw.guildId"),
  ])[0];

  if (channel === "discord") {
    if (channelId) {
      return { channel, to: channelId, toKind: "channel", guildId, channelId, userId };
    }
    if (userId) {
      return { channel, to: userId, toKind: "user", guildId, channelId: null, userId };
    }
  }
  return { channel, to: null, toKind: null, guildId, channelId, userId };
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

function runCommand(cmd, args, cwd = process.cwd()) {
  return new Promise((resolve) => {
    const child = spawn(cmd, args, {
      cwd,
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

function parseCronAddJson(s) {
  if (!s || typeof s !== "string") return null;
  try {
    const parsed = JSON.parse(s);
    const obj = asRecord(parsed);
    return {
      id: typeof obj.id === "string" ? obj.id : typeof obj.jobId === "string" ? obj.jobId : null,
      nextRunAt:
        typeof obj.nextRunAt === "string"
          ? obj.nextRunAt
          : typeof obj.next_run_at === "string"
            ? obj.next_run_at
            : null,
    };
  } catch {
    return null;
  }
}

function parseCronAddText(s) {
  if (!s || typeof s !== "string") return { id: null, nextRunAt: null };
  const idMatch =
    s.match(/\bjob(?:Id)?\s*[:=]\s*([A-Za-z0-9_-]+)/i) ||
    s.match(/\bcreated\b[^\n]*\b([A-Za-z0-9_-]{8,})\b/i);
  const nextMatch = s.match(/\bnext(?:\s+run(?:\s+at)?)?\s*[:=]\s*([^\n]+)/i);
  return {
    id: idMatch ? idMatch[1] : null,
    nextRunAt: nextMatch ? nextMatch[1].trim() : null,
  };
}

async function addCronJobFromCommand(ctx, resolved, delaySpec, promptText) {
  const route = channelRouting(ctx);
  const jobName = `recheck-${Date.now()}`;
  const message = promptText.trim();
  const argsBase = [
    "cron",
    "add",
    "--name",
    jobName,
    "--at",
    delaySpec,
    "--session",
    "isolated",
    "--message",
    message,
    "--expect-final",
    "--timeout-seconds",
    "300",
    "--delete-after-run",
  ];

  if (resolved?.agentId) {
    argsBase.push("--agent", resolved.agentId);
  }

  if (route.channel && route.to) {
    argsBase.push("--announce", "--channel", route.channel, "--to", route.to);
  } else {
    argsBase.push("--announce");
  }

  let result = await runCommand("openclaw", [...argsBase, "--json"], resolved.workspace);
  let parsed = parseCronAddJson(result.stdout);
  if (result.code !== 0 && /unknown option|unknown argument|unknown flag/i.test(result.stderr)) {
    result = await runCommand("openclaw", argsBase, resolved.workspace);
    parsed = parseCronAddJson(result.stdout) || parseCronAddText(result.stdout);
  } else if (!parsed) {
    parsed = parseCronAddText(result.stdout);
  }

  return {
    result,
    parsed,
    jobName,
    route,
  };
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

  api.registerCommand(
    "/recheckin",
    async (ctx) => {
      const args = parseArgs(ctx);
      const config = ctx?.config || {};
      const resolved = resolveWorkspaceAndAgent(config, ctx, args);
      if ("error" in resolved) return `⚠️ ${resolved.error}`;

      const positional = [];
      for (let i = 0; i < args.length; i += 1) {
        const a = args[i];
        if ((a === "--repo" || a === "-r" || a === "--agent" || a === "-a") && args[i + 1]) {
          i += 1;
          continue;
        }
        positional.push(a);
      }

      const delaySpec = parseDurationSpec(positional[0] || "");
      if (!delaySpec) {
        return [
          "⚠️ Usage: `/recheckin <delay> <what to re-check> [--agent <id> | --repo <path>]`",
          "Examples:",
          "- `/recheckin 5m Re-check logs and confirm the local stack is still healthy.`",
          "- `/recheckin 15m Verify the scraper job completed and report the counts.`",
        ].join("\n");
      }

      const messageBody = positional.slice(1).join(" ").trim();
      if (!messageBody) {
        return "⚠️ Provide what to re-check. Example: `/recheckin 5m Re-check the local stack and report status.`";
      }

      const promptText = [
        "Scheduled follow-up check.",
        `Workspace: ${resolved.workspace}`,
        resolved.agentId ? `Agent: ${resolved.agentId}` : "",
        `Task: ${messageBody}`,
        "Report the result clearly and include pass/fail and next action.",
      ]
        .filter(Boolean)
        .join("\n");

      const { result, parsed, jobName, route } = await addCronJobFromCommand(ctx, resolved, delaySpec, promptText);
      if (result.code !== 0) {
        return [
          "⚠️ Failed to create cron checkback job.",
          `Exit code: ${result.code}`,
          result.stderr ? `stderr:\n${trimOut(result.stderr, 1500)}` : "",
          result.stdout ? `stdout:\n${trimOut(result.stdout, 1500)}` : "",
          "",
          "Do not promise a timed follow-up unless the cron job is created.",
        ]
          .filter(Boolean)
          .join("\n\n");
      }

      const jobId = parsed?.id || "(id not returned by CLI)";
      const nextRun = parsed?.nextRunAt || `in ${delaySpec}`;
      const delivery =
        route.channel && route.to
          ? `${route.channel}:${route.toKind || "target"}:${route.to}`
          : "announce (default route)";
      const commandPreview = `openclaw cron add --name ${shellQuote(jobName)} --at ${shellQuote(delaySpec)} ...`;

      return [
        "✅ Scheduled real follow-up.",
        `- jobId: ${jobId}`,
        `- runs: ${nextRun}`,
        `- agent: ${resolved.agentId || "auto"}`,
        `- repo: \`${resolved.workspace}\``,
        `- delivery: ${delivery}`,
        `- task: ${messageBody}`,
        "",
        "This makes the timed promise real (Gateway cron job created).",
        `CLI: \`${commandPreview}\``,
      ].join("\n");
    },
    {
      description: "Create a real timed follow-up using OpenClaw cron and announce back to this channel",
      argsHint: "<5m|10m|1h|1d> <task> [--agent <id> | --repo <path>]",
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
