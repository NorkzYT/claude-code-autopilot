FROM python:3.11-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    git \
  && rm -rf /var/lib/apt/lists/* \
  && git clone --depth=1 https://github.com/novnc/noVNC.git /opt/novnc \
  && git clone --depth=1 https://github.com/novnc/websockify.git /opt/novnc/utils/websockify

COPY docker/browser-viewer/entrypoint.sh /usr/local/bin/browser-viewer-entrypoint
RUN chmod +x /usr/local/bin/browser-viewer-entrypoint

ENTRYPOINT ["browser-viewer-entrypoint"]
CMD []
