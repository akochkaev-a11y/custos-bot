#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
from urllib.request import Request,urlopen
from urllib.error import HTTPError
from html.parser import HTMLParser
import json,re
class Form(HTMLParser):
 def __init__(self):
  super().__init__();self.forms=[];self.fields=[];self.form=None
 def handle_starttag(self,tag,attrs):
  a=dict(attrs)
  if tag=='form':
   self.form={'action':a.get('action',''),'method':a.get('method','get')};self.forms.append(self.form)
  name=a.get('name','')
  if tag in ('input','select') and name.startswith('AnketaSearch['):
   self.fields.append({'name':name,'type':a.get('type',tag),'value':a.get('value',''),'checked':'checked' in a,'form':self.form})
 def handle_endtag(self,tag):
  if tag=='form':self.form=None
url='https://atolin.ru/anketa/search'
try:
 with urlopen(Request(url,headers={'User-Agent':'Mozilla/5.0','Cache-Control':'no-cache'}),timeout=15) as r:
  status=r.status;raw=r.read(200000).decode('utf-8','replace')
except HTTPError as e:
 status=e.code;raw=e.read(200000).decode('utf-8','replace')
p=Form();p.feed(raw)
print('PUBLIC_SEARCH_STATUS',status)
print('PUBLIC_SEARCH_FORM_FIELDS',json.dumps(p.fields,ensure_ascii=False))
print('PUBLIC_SEARCH_TITLE',re.sub('<[^>]+>','',next(iter(re.findall(r'<title[^>]*>(.*?)</title>',raw,re.S|re.I)),''))[:150])
PY
