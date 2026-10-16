#!/usr/bin/env bash
set -uo pipefail
date -u
systemctl show atolin-assistant nginx -p Id -p ActiveState -p SubState -p NRestarts -p MemoryCurrent -p ExecMainStartTimestamp
df -h / /var/lib/atolin-assistant
free -m
python3 - <<'PY'
from pathlib import Path
from collections import Counter
import re,subprocess,json
for p in Path('/var/log/nginx').glob('*error*'):
 if not p.is_file() or p.suffix=='.gz':continue
 counts=Counter(); times={}
 for l in p.read_text(errors='replace').splitlines():
  if '2026/10/16' not in l:continue
  for reason in ['connect() failed','upstream prematurely closed connection','upstream timed out','no live upstreams','Connection refused','Permission denied','No space left on device','too big header','SSL_do_handshake() failed']:
   if reason in l:counts[reason]+=1;times[reason]=l[:19]
 print('NGINX_ERRORS',p.name,dict(counts),'last',times)
for p in Path('/var/log/nginx').glob('*access*'):
 if not p.is_file() or p.suffix=='.gz':continue
 counts=Counter(); first={}; last={}
 for l in p.read_text(errors='replace').splitlines():
  if '16/Oct/2026' not in l:continue
  m=re.search(r'\[([^]]+)\] "([A-Z]+) ([^ ]+) HTTP/[^"]+" (\d+)',l)
  if not m:continue
  t,method,path,status=m.groups()
  if path.split('?')[0] not in ['/v1/reports','/health']:continue
  key=method+' '+path.split('?')[0]+' '+status
  counts[key]+=1;first.setdefault(key,t);last[key]=t
 print('NGINX_ACCESS',p.name,json.dumps(dict(counts)), 'first',first,'last',last)
raw=subprocess.run(['journalctl','-u','atolin-assistant','--since','2026-10-16 12:00:00 UTC','--no-pager','-o','cat'],capture_output=True,text=True).stdout
counts=Counter()
for l in raw.splitlines():
 for term in ['ENOSPC','ENOMEM','EACCES','EMFILE','SyntaxError','TypeError','RangeError','heap out of memory','Killed','Started','Stopped','Failed','error','Error']:
  if term in l:counts[term]+=1
print('SERVICE_LOG_CATEGORIES',dict(counts))
PY
for target in http://127.0.0.1:3001/health https://87.228.13.236/health https://87-228-13-236.sslip.io/health; do
 curl -sS -o /dev/null --connect-timeout 4 --max-time 8 -w "HEALTH $target status=%{http_code} time=%{time_total}\n" "$target" || true
done
