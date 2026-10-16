#!/usr/bin/env bash
set -uo pipefail
python3 - <<'PY'
from pathlib import Path
import subprocess,json
sizes=sorted([p.stat().st_size for p in Path('/var/lib/atolin-assistant/users').glob('*/reports.jsonl')],reverse=True)
print('REPORT_HISTORY_BYTES',sizes)
print('REPORT_HISTORY_TOTAL_BYTES',sum(sizes))
raw=subprocess.run(['journalctl','-u','atolin-assistant','--since','2026-10-16 00:00:00 UTC','--no-pager','-o','json'],capture_output=True,text=True).stdout
events=[]
for line in raw.splitlines():
 try:r=json.loads(line)
 except:continue
 if "Failed with result 'oom-kill'" in r.get('MESSAGE',''):events.append(r.get('__REALTIME_TIMESTAMP'))
print('OOM_EVENT_COUNT',len(events),'FIRST_TIMESTAMP_US',events[0] if events else None,'LAST_TIMESTAMP_US',events[-1] if events else None)
PY
