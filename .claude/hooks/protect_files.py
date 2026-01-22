#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path, PurePosixPath


# Temporary escape hatch (set before starting claude):
#   export CLAUDE_ALLOW_PROTECTED_EDITS=1
ALLOW_OVERRIDE_ENV = "CLAUDE_ALLOW_PROTECTED_EDITS"

# Conservative defaults. Tune to your org.
PROTECTED_GLOBS = [
    # .env and variants
    "**/.env",
    "**/.env.*",

    # Common key/cert material
    "**/*.pem",
    "**/*.key",
    "**/*.p12",
    "**/*.pfx",
    "**/id_rsa",
    "**/id_rsa.*",
    "**/id_ed25519",
    "**/id_ed25519.*",

    # Common secret files
    "**/*secret*",
    "**/*secrets*",
    "**/.aws/**",
    "**/.ssh/**",
    "**/*kubeconfig*",

    # Common prod config patterns
    "**/docker-compose.prod*.yml",
    "**/docker-compose.production*.yml",
    "**/.github/workflows/*deploy*.yml",
    "**/infra/prod/**",
    "**/k8s/prod/**",
    "**/terraform/prod/**",
    "**/config/prod/**",
    "**/config/production/**",
]


def to_project_relative(path_str: str, project_dir: str) -> str:
    """
    Convert an absolute path to project-relative (POSIX style) if possible.
    Keep as-is (normalized) if not under project dir.
    """
    p = Path(path_str)
    proj = Path(project_dir)

    try:
        rp = p.resolve()
        rproj = proj.resolve()
        if str(rp).startswith(str(rproj) + os.sep) or rp == rproj:
            rel = rp.relative_to(rproj).as_posix()
            return rel
    except Exception:
        pass

    # Fall back: normalize separators
    return p.as_posix().lstrip("./")


def is_protected(rel_posix: str) -> bool:
    rel = PurePosixPath(rel_posix)
    for pat in PROTECTED_GLOBS:
        if rel.match(pat):
            return True
    return False


def extract_paths(tool_name: str, tool_input: dict) -> list[str]:
    paths: list[str] = []

    # Write/Edit have file_path. :contentReference[oaicite:4]{index=4}
    fp = tool_input.get("file_path")
    if isinstance(fp, str) and fp.strip():
        paths.append(fp.strip())

    # MultiEdit varies; handle common shapes defensively.
    # If Claude passes multiple edits with file paths.
    edits = tool_input.get("edits")
    if isinstance(edits, list):
        for e in edits:
            if isinstance(e, dict):
                p = e.get("file_path") or e.get("path")
                if isinstance(p, str) and p.strip():
                    paths.append(p.strip())

    # Dedup
    out: list[str] = []
    seen: set[str] = set()
    for p in paths:
        if p not in seen:
            out.append(p)
            seen.add(p)
    return out


def main() -> int:
    if os.getenv(ALLOW_OVERRIDE_ENV) == "1":
        return 0

    project_dir = os.getenv("CLAUDE_PROJECT_DIR") or os.getcwd()

    try:
        payload = json.load(sys.stdin)
    except Exception as e:
        print(f"protect_files: invalid JSON input: {e}", file=sys.stderr)
        return 0  # don’t break the session

    tool_name = payload.get("tool_name", "")
    tool_input = payload.get("tool_input", {}) or {}

    if tool_name not in ("Write", "Edit", "MultiEdit"):
        return 0

    if not isinstance(tool_input, dict):
        return 0

    paths = extract_paths(tool_name, tool_input)
    for p in paths:
        rel = to_project_relative(p, project_dir)
        if is_protected(rel):
            print(
                "\n".join(
                    [
                        f"Blocked edit to protected file: {rel}",
                        "This kit blocks .env*, secret material, and common prod config paths.",
                        f"To override temporarily: export {ALLOW_OVERRIDE_ENV}=1 (then restart Claude).",
                        "Or edit .claude/hooks/protect_files.py to adjust PROTECTED_GLOBS.",
                    ]
                ),
                file=sys.stderr,
            )
            return 2  # Exit code 2 blocks PreToolUse tool call. :contentReference[oaicite:5]{index=5}

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
