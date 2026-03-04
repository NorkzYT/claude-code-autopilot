FROM node:22-bookworm-slim

# System dependencies
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    git \
    jq \
    openssh-client \
    procps \
    python3 \
  && rm -rf /var/lib/apt/lists/*

# Install Claude Code CLI
RUN npm install -g @anthropic-ai/claude-code@latest

# Non-root user for safety
RUN useradd -m -u 1000 -s /bin/bash ralph

COPY docker/ralph/entrypoint.sh /usr/local/bin/ralph-entrypoint
RUN chmod +x /usr/local/bin/ralph-entrypoint

USER ralph
WORKDIR /workspace

ENTRYPOINT ["ralph-entrypoint"]
