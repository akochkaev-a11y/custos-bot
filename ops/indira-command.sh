#!/usr/bin/env bash
set -uo pipefail
systemctl show atolin-assistant -p Result -p ExecMainCode -p ExecMainStatus -p MemoryMax -p MemoryPeak -p OOMPolicy -p NRestarts
python3 - <<'PY'
import subprocess,re
from collections import Counter
raw=subprocess.run(['journalctl','-u','atolin-assistant','--since','2026-10-16 12:00:00 UTC','--no-pager','-o','cat'],capture_output=True,text=True).stdout
counts=Counter()
for l in raw.splitlines():
 if any(t in l for t in ['Main process exited','Failed with result','Consumed','Scheduled restart','code=','FATAL','ERR_','Unhandled','uncaught','signal','heap','allocation','status=']):
  l=re.sub(r'[a-f0-9]{8}-[a-f0-9-]{27,}', '[ID]',l)
  l=re.sub(r'https?://\S+', '[URL]',l)
  if len(l)<350 and not any(t in l.lower() for t in ['authorization','bearer','token','password','body=']):counts[l]+=1
print('CRASH_MESSAGES',dict(counts))
from pathlib import Path
root=Path('/opt/atolin-assistant')
print('SERVER_FILES',[str(p.relative_to(root)) for p in (root/'server').glob('*.cjs')])
print('DEPLOYED_REVISION',subprocess.run(['git','-C',str(root),'rev-parse','HEAD'],capture_output=True,text=True).stdout.strip())
PY
