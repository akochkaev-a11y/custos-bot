#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
from pathlib import Path
from collections import Counter
import json,re
replies=set();visits=set();totals=set()
for p in Path('/var/lib/atolin-assistant/users').glob('*/reports.jsonl'):
 with p.open() as f:
  for raw in f:
   try:r=json.loads(raw)
   except:continue
   if r.get('kind')!='dialogs':continue
   b=r.get('body','')
   for line in b.splitlines():
    if not line.startswith('2026-10-16 '):continue
    m=re.search(r'^([0-9-]+ [0-9:.]+).* · ACTION .*отчёт=(\d+) \| Автоответ подтверждён:',line)
    if m:replies.add((m[1],int(m[2])))
    m=re.search(r'^([0-9-]+ [0-9:.]+).* · ACTION .*отчёт=(\d+) \| Посещения завершены: открыто (\d+), пропущено (\d+), с перепиской (\d+)',line)
    if m:visits.add(tuple(m.groups()))
   if r.get('key','').endswith('.1'):
    m=re.search(r'Всего подтверждённых автоответов:\s*(\d+)',b[:5500])
    if m:totals.add((r['started'],int(m[1])))
print('CONFIRMED_REPLY_EVENTS_BY_CYCLE',dict(sorted(Counter(c for _,c in replies).items())))
print('CONFIRMED_REPLY_EVENTS_TOTAL',len(replies))
print('CONFIRMED_REPLY_TIMES',sorted(replies))
print('COMPLETED_VISITS',sorted(visits))
print('CUMULATIVE_COUNTER_SNAPSHOTS',sorted(totals))
PY
