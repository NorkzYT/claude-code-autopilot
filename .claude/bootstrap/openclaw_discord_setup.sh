#!/usr/bin/env bash
set -euo pipefail

# Discord bot setup helper for OpenClaw
# Guides user through Discord bot creation and configuration

log()  { printf "\n==> %s\n" "$*"; }
warn() { printf "\n[WARN] %s\n" "$*" >&2; }
has()  { command -v "$1" >/dev/null 2>&1; }

if ! has openclaw; then
  warn "OpenClaw is not installed. Run install.sh --with-openclaw first."
  exit 1
fi

echo ""
echo "=============================================="
echo "  DISCORD BOT SETUP FOR OPENCLAW"
echo "=============================================="
echo ""
echo "  This wizard helps you connect OpenClaw to Discord."
echo ""
echo "  Prerequisites:"
echo "    - A Discord server where you have admin permissions"
echo "    - A web browser to create the Discord application"
echo ""
echo "=============================================="
echo ""

# Step 1: Create Discord Application
echo "Step 1: Create a Discord Application"
echo "-------------------------------------"
echo ""
echo "  1. Go to: https://discord.com/developers/applications"
echo "  2. Click 'New Application'"
echo "  3. Name it: 'Claude Code Autopilot' (or your preference)"
echo "  4. Click 'Create'"
echo ""

# Step 2: Create Bot
echo "Step 2: Create the Bot"
echo "----------------------"
echo ""
echo "  1. In the application settings, click 'Bot' in the left sidebar"
echo "  2. Click 'Add Bot' -> 'Yes, do it!'"
echo "  3. Under 'Privileged Gateway Intents', enable:"
echo "     - MESSAGE CONTENT INTENT"
echo "     - SERVER MEMBERS INTENT (optional)"
echo "  4. Click 'Reset Token' to generate a bot token"
echo "  5. Copy the token (you'll need it next)"
echo ""

# Step 3: Invite Bot to Server
echo "Step 3: Invite Bot to Your Server"
echo "----------------------------------"
echo ""
echo "  1. Click 'OAuth2' -> 'URL Generator' in the left sidebar"
echo "  2. Under 'Scopes', check: bot, applications.commands"
echo "  3. Under 'Bot Permissions', check:"
echo "     - Send Messages"
echo "     - Read Message History"
echo "     - Use Slash Commands"
echo "     - Embed Links"
echo "     - Attach Files"
echo "  4. Copy the generated URL and open it in your browser"
echo "  5. Select your server and click 'Authorize'"
echo ""

# Step 4: Configure OpenClaw
echo "Step 4: Connect to OpenClaw"
echo "----------------------------"
echo ""
read -rp "  Paste your Discord bot token: " BOT_TOKEN

if [[ -z "$BOT_TOKEN" ]]; then
  warn "No token provided. You can configure later with:"
  echo "  openclaw channels add discord"
  exit 0
fi

# Add Discord channel to OpenClaw
if openclaw channels add discord --token "$BOT_TOKEN" 2>/dev/null; then
  log "Discord channel configured successfully!"
else
  warn "Failed to configure Discord channel."
  echo "  Try manually: openclaw channels add discord --token <your-token>"
  exit 1
fi

# Step 5: Test connection
echo ""
echo "Step 5: Test Connection"
echo "-----------------------"
echo ""

read -rp "  Send a test message to Discord? (y/N): " TEST_MSG

if [[ "$TEST_MSG" =~ ^[Yy] ]]; then
  if openclaw notify "Hello from Claude Code Autopilot! Bot is connected." 2>/dev/null; then
    log "Test message sent! Check your Discord server."
  else
    warn "Test message failed. Check your bot token and server permissions."
  fi
fi

echo ""
log "Discord setup complete!"
echo ""
echo "  Usage from Discord:"
echo "    !status      -- Project status"
echo "    !test        -- Run tests"
echo "    !ship <task> -- Execute a task"
echo "    !ask <q>     -- Query codebase"
echo ""
echo "  See: .claude/docs/openclaw-remote-commands.md for full reference"
echo ""
