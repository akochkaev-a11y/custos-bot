#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
from urllib.request import Request,urlopen
from urllib.parse import urlencode
from urllib.error import HTTPError
import re,json
base='https://atolin.ru/anketa/search'
cases=[('plain',[]),('native_form_gender_1',[('AnketaSearch[gender]',''),('AnketaSearch[gender][]','1'),('AnketaSearch[agefrom]',''),('AnketaSearch[ageto]','25'),('AnketaSearch[location_id]','')]),('native_form_gender_0',[('AnketaSearch[gender]',''),('AnketaSearch[gender][]','0'),('AnketaSearch[agefrom]',''),('AnketaSearch[ageto]','25'),('AnketaSearch[location_id]','')])]
for name,params in cases:
 try:
  with urlopen(Request(base+('?' +urlencode(params) if params else ''),headers={'User-Agent':'Mozilla/5.0','Cache-Control':'no-cache'}),timeout=15) as r:status=r.status;raw=r.read(200000).decode('utf-8','replace')
 except HTTPError as e:status=e.code;raw=e.read(200000).decode('utf-8','replace')
 title=re.sub('<[^>]+>','',next(iter(re.findall(r'<title[^>]*>(.*?)</title>',raw,re.S|re.I)),''))[:150]
 print('SEARCH_VARIANT',json.dumps(dict(variant=name,status=status,title=title,searchForm='AnketaSearch' in raw),ensure_ascii=False))
PY
