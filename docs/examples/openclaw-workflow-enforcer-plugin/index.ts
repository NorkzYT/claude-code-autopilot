/**
 * Example OpenClaw plugin skeleton (design example)
 *
 * Purpose:
 * - show how a plugin could validate `.openclaw/workflow-report.local.json`
 * - pair with `.claude/scripts/openclaw-local-workflow.sh`
 *
 * Adjust event names and helper APIs to your OpenClaw version.
 */

export default async function register(api: any) {
  // Example: register a hook to inspect commands or completion/report events.
  // `command:new` is documented. For stricter gating, use the relevant completion
  // event from your OpenClaw version and run the same report check there.
  api.registerHook(
    "command:new",
    async (ctx: any) => {
      // Example only: do not block normal commands here.
      // Use this area for logging or tagging when engineering workflows start.
      api.logger?.debug?.("workflow-enforcer-example observed command:new", {
        command: ctx?.command?.name,
      });
      return { ok: true };
    },
    {
      id: "workflow-enforcer-example.command-new",
      description: "Example hook for local workflow wrapper integration",
    },
  );

  // Optional custom command wrapper (concept)
  // The plugin can register a command that runs your local workflow wrapper and
  // then checks `.openclaw/workflow-report.local.json` before returning success.
  // Implement with the command registration API for your OpenClaw version.
}
