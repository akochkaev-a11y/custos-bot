#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
from pathlib import Path
import json,re,datetime
latest={}
for p in Path('/var/lib/atolin-assistant/users').glob('*/reports.jsonl'):
 with p.open() as f:
  for line in f:
   try:r=json.loads(line)
   except:continue
   if r.get('ended',0)<1792098000000:continue
   b=r.get('body','')[:5500]
   if r.get('kind')=='dialogs':
    latest[r['key']]={'started':r['started'],'ended':r['ended'],'title':r['title'],'summary':b}
for key,r in sorted(latest.items(),key=lambda x:x[1]['started']):
 if not key.endswith('.1'):continue
 b=r['summary'];cycle=re.search(r'Рабочий цикл поиска: №(\d+)',b)
 if not cycle:continue
 total=re.search(r'Всего подтверждённых автоответов:\s*(\d+)',b)
 session=re.search(r'Автоответов за текущий запуск:\s*(\d+)',b)
 visit=re.search(r'Посещения: пройдено (\d+), открыто (\d+), пропущено (\d+)',b)
 print(json.dumps({'start':datetime.datetime.fromtimestamp(r['started']/1000,datetime.timezone(datetime.timedelta(hours=3))).strftime('%m-%d %H:%M:%S'),'end':datetime.datetime.fromtimestamp(r['ended']/1000,datetime.timezone(datetime.timedelta(hours=3))).strftime('%m-%d %H:%M:%S'),'cycle':int(cycle[1]),'result':r['title'].split(' · ')[1],'total':int(total[1]) if total else None,'session':int(session[1]) if session else None,'visit':[int(n) for n in visit.groups()] if visit else None}))
PY
