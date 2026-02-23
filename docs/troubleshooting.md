# Troubleshooting

## Common Issues

| Issue | What to check |
|-------|---------------|
| Autopilot not launching | Restart Claude Code and confirm `.claude/settings.local.json` exists |
| Command blocked | Review `.claude/hooks/guard_bash.py` and add a safe allowlist rule if needed |
| File edit blocked | Check protected file markers and sentinel rules |
| Formatting not working | Make sure the repo has formatter config files (`.prettierrc*`, `pyproject.toml`) |
| Hooks not running | Ensure the settings file used by Claude includes the hook config |
| `Ctrl+G` opens `nano` | Confirm VS Code integration requirements from `docs/editor.md` |

## Validate the kit setup

```bash
./.claude/extras/doctor.sh
```

## OpenClaw Troubleshooting

Use the OpenClaw docs for gateway, Discord, and browser issues:

- `.claude/docs/openclaw-integration.md`
- `.claude/docs/openclaw-remote-commands.md`
- `.claude/docs/openclaw-commands.md`

Useful commands:

```bash
openclaw status
openclaw gateway status
openclaw logs --follow
```
