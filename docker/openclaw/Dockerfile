FROM ghcr.io/openclaw/openclaw:latest

USER root

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    chromium \
    curl \
    fluxbox \
    git \
    jq \
    openssh-client \
    procps \
    python3 \
    x11vnc \
    xvfb \
  && rm -rf /var/lib/apt/lists/*

COPY docker/openclaw/entrypoint.sh /usr/local/bin/openclaw-entrypoint
RUN chmod +x /usr/local/bin/openclaw-entrypoint

USER node
WORKDIR /home/node

ENV OPENCLAW_STATE_DIR=/home/node/.openclaw \
    DISPLAY=:99 \
    OPENCLAW_BROWSER_DOWNLOADS_DIR=/home/node/.openclaw/downloads

ENTRYPOINT ["openclaw-entrypoint"]
CMD ["gateway"]
