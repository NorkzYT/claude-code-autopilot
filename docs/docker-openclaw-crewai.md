# Docker Stacks: OpenClaw and CrewAI

OpenClaw and CrewAI are intentionally split into separate compose files so users can run only what they need.

## Files

- `docker-compose.openclaw.yml`
- `docker-compose.crewai.yml`
- `docker/openclaw/Dockerfile`
- `docker/openclaw/entrypoint.sh`
- `docker/crewai/Dockerfile`
- `docker/crewai/entrypoint.sh`
- `docker/cliproxyapi/config.yaml` (optional proxy profile for CrewAI stack)

## Prerequisites

- Docker + Docker Compose plugin
- Host repos under `/opt/repos` (or set `HOST_REPOS_DIR`)

## OpenClaw Stack (Only OpenClaw)

Start:

```bash
docker compose -f docker-compose.openclaw.yml up -d
```

Logs/status:

```bash
docker compose -f docker-compose.openclaw.yml logs -f openclaw-gateway
docker exec -it openclaw-gateway openclaw status
```

Stop:

```bash
docker compose -f docker-compose.openclaw.yml down
```

## CrewAI Stack (Only CrewAI)

Start runner:

```bash
docker compose -f docker-compose.crewai.yml up -d crewai-runner
```

Optional proxy profile:

```bash
docker compose -f docker-compose.crewai.yml --profile proxy up -d cliproxyapi
```

Proxy endpoints:
- OpenAI-compatible API: `http://localhost:8317/v1`
- Management UI: `http://localhost:8085`

Run a repo workflow:

```bash
docker exec -it crewai-runner crewai-entrypoint run /opt/repos/<repo-name> --goal "Increase traction and paying customers"
```

Stop:

```bash
docker compose -f docker-compose.crewai.yml down
```

## Mounting Repos

Both compose files bind:

- `/opt/repos` (host) -> `/opt/repos` (container)

Override host path:

```bash
HOST_REPOS_DIR=/path/to/repos docker compose -f docker-compose.openclaw.yml up -d
HOST_REPOS_DIR=/path/to/repos docker compose -f docker-compose.crewai.yml up -d crewai-runner
```

## OpenClaw Sandboxing Notes

OpenClaw sandboxing behavior and policy controls are documented at:

- `https://docs.openclaw.ai/gateway/sandboxing`

If you need containerized command execution against host Docker workloads, you may need additional mounts/permissions (for example Docker socket). Keep those disabled by default unless required.
