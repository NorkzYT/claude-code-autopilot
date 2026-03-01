FROM python:3.11-slim

RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
  && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir uv

RUN useradd -m -u 1000 -s /bin/bash crewai

COPY docker/crewai/entrypoint.sh /usr/local/bin/crewai-entrypoint
RUN chmod +x /usr/local/bin/crewai-entrypoint

USER crewai
WORKDIR /workspace

ENV PYTHONUNBUFFERED=1

ENTRYPOINT ["crewai-entrypoint"]
CMD ["sleep", "infinity"]
