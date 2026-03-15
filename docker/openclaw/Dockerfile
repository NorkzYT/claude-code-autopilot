FROM node:22-bookworm-slim

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

RUN npm install -g openclaw@latest

RUN useradd -m -u 1000 -s /bin/bash openclaw

COPY docker/openclaw/entrypoint.sh /usr/local/bin/openclaw-entrypoint
RUN chmod +x /usr/local/bin/openclaw-entrypoint

USER openclaw
WORKDIR /home/openclaw

ENV OPENCLAW_STATE_DIR=/home/openclaw/.openclaw \
    DISPLAY=:99 \
    OPENCLAW_BROWSER_DOWNLOADS_DIR=/home/openclaw/.openclaw/downloads

ENTRYPOINT ["openclaw-entrypoint"]
CMD ["gateway"]
