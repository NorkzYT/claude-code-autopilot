FROM ghcr.io/openclaw/openclaw:latest

USER root

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    chromium \
    curl \
    dbus \
    fluxbox \
    git \
    gosu \
    jq \
    openssh-client \
    procps \
    python3 \
    x11vnc \
    xvfb \
  && rm -rf /var/lib/apt/lists/*

# Install Docker CLI (not the daemon) so agents can run docker/compose
# commands against the host Docker socket mounted at /var/run/docker.sock.
RUN install -m 0755 -d /etc/apt/keyrings \
  && curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc \
  && chmod a+r /etc/apt/keyrings/docker.asc \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian bookworm stable" \
     > /etc/apt/sources.list.d/docker.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
    docker-ce-cli \
    docker-compose-plugin \
  && rm -rf /var/lib/apt/lists/*

# Install Claude Code CLI so analyze_repo.sh --deep can run claude --print
# for codebase scanning and PROJECT.md generation inside the container.
RUN npm install -g @anthropic-ai/claude-code && npm cache clean --force

RUN echo 'export CHROMIUM_FLAGS="$CHROMIUM_FLAGS --no-sandbox --disable-setuid-sandbox"' \
    > /etc/chromium.d/docker

# Replace fbsetbg with a no-op — wallpapers are unnecessary in a headless
# container and the default Debian theme triggers fbsetbg which fails
# without an image viewer, producing an xmessage error dialog.
RUN printf '#!/bin/sh\nexit 0\n' > /usr/bin/fbsetbg

# Set container-wide umask to 0022 so all files (including openclaw.json)
# are created world-readable. This applies to the gateway, docker exec,
# and compose exec sessions. Without this, OpenClaw writes config as 600
# which breaks cross-UID access on bind mounts.
RUN echo 'umask 0022' >> /etc/bash.bashrc \
    && echo 'umask 0022' >> /etc/profile.d/umask.sh

COPY docker/openclaw/entrypoint.sh /usr/local/bin/openclaw-entrypoint
RUN chmod +x /usr/local/bin/openclaw-entrypoint

WORKDIR /home/node

ENV OPENCLAW_STATE_DIR=/home/node/.openclaw \
    DISPLAY=:99 \
    OPENCLAW_BROWSER_DOWNLOADS_DIR=/home/node/.openclaw/downloads

ENTRYPOINT ["openclaw-entrypoint"]
CMD ["gateway"]
