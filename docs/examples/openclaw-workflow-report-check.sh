#!/usr/bin/env bash
set -euo pipefail

REPO="${1:-$(pwd)}"
REPORT="$REPO/.openclaw/workflow-report.local.json"

if [[ ! -f "$REPORT" ]]; then
  echo "missing report: $REPORT" >&2
  exit 2
fi

python3 - "$REPORT" <<'PY'
import json, sys
path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as f:
    data = json.load(f)
steps = (data or {}).get('steps') or {}
required = ['build', 'run_local', 'test', 'confirm']
failed = []
for name in required:
    status = steps.get(name)
    if status != 'passed':
        failed.append((name, status))
if failed:
    for name, status in failed:
        print(f'{name}: {status}', file=sys.stderr)
    sys.exit(1)
print('workflow report OK')
PY
