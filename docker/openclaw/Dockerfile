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
