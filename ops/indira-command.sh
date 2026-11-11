#!/usr/bin/env bash
set -euo pipefail
printf 'Custos DNS and proxy checks\n'
python3 -u - <<'PY'
import socket,ssl,urllib.request,json,concurrent.futures
from pathlib import Path
for line in Path('/etc/hosts').read_text().splitlines():
    if 'telegram' in line.lower(): print('Hosts entry:',line)
ips=set()
for endpoint in ('https://dns.google/resolve?name=api.telegram.org&type=A','https://cloudflare-dns.com/dns-query?name=api.telegram.org&type=A'):
    try:
        req=urllib.request.Request(endpoint,headers={'Accept':'application/dns-json'})
        with urllib.request.urlopen(req,timeout=8) as r: data=json.load(r)
        answers=[x['data'] for x in data.get('Answer',[]) if x['type']==1]
        print('Independent DNS',endpoint.split('/')[2],answers)
        ips.update(answers)
    except Exception as e: print('Independent DNS failed',type(e).__name__)
def probe(ip):
    try:
        with socket.create_connection((ip,443),timeout=5) as s:
            with ssl.create_default_context().wrap_socket(s,server_hostname='api.telegram.org') as tls:
                print('Verified Telegram TLS',ip,tls.version())
    except Exception as e: print('Telegram address',ip,type(e).__name__)
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:list(pool.map(probe,sorted(ips)))
for port in (1080,10808,7890,8080,3128):
    try:
        with socket.create_connection(('127.0.0.1',port),timeout=1):
            print('Local proxy candidate',port)
    except OSError: pass
print('Network checks complete')
PY
