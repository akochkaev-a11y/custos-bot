#!/usr/bin/env bash
set -euo pipefail
systemctl show atolin-assistant -p ActiveState -p NRestarts -p MemoryCurrent -p MemoryPeak -p MemoryMax -p ExecMainStartTimestamp
python3 - <<'PY'
import subprocess,json
raw=subprocess.run(['journalctl','-u','atolin-assistant','--since','2026-10-16 15:48:15 UTC','--no-pager','-o','cat'],capture_output=True,text=True).stdout
print('POST_DEPLOY_OOM_EVENTS',raw.count("Failed with result 'oom-kill'"))
from pathlib import Path
print('REPORT_HISTORY_BYTES',sorted(p.stat().st_size for p in Path('/var/lib/atolin-assistant/users').glob('*/reports.jsonl')))
PY
systemctl is-active atolin-assistant nginx geostrategy geostrategy-apk
