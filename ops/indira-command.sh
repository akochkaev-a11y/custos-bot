#!/usr/bin/env bash
set -euo pipefail
umask 077
printf 'Custos recovery diagnostics 2026-11-11\n'
date -u
for p in /opt/custos/custos.py /etc/custos/config.json /var/lib/custos/archive.sqlite3; do
  if test -f "$p"; then stat -c '%n %s bytes modified=%y' "$p"; else printf 'Missing: %s\n' "$p"; fi
done
systemctl show custos.service -p LoadState -p ActiveState -p SubState -p Result -p NRestarts -p UnitFileState --no-pager || true
python3 - <<'PY'
import socket,ssl,urllib.request,urllib.error,json,time
from pathlib import Path
host='api.telegram.org'
try:
    ips=sorted({x[4][0] for x in socket.getaddrinfo(host,443,type=socket.SOCK_STREAM)})
    print('Telegram DNS:', ', '.join(ips))
except OSError as e:
    print('DNS failed:', type(e).__name__)
for url in ['https://api.telegram.org','https://telegram.org','https://github.com']:
    start=time.monotonic()
    try:
        with urllib.request.urlopen(url,timeout=10) as r:
            print(url, 'HTTP',r.status, 'seconds',round(time.monotonic()-start,2))
    except urllib.error.HTTPError as e:
        print(url,'HTTP',e.code)
    except Exception as e:
        print(url,'failed',type(e).__name__,'seconds',round(time.monotonic()-start,2))
p=Path('/etc/custos/config.json')
if p.exists():
    try:
        cfg=json.loads(p.read_text())
        print('Config parsed; token present:',bool(cfg.get('token')),'setup code present:',bool(cfg.get('setup_code')))
        for method in ('getMe','getWebhookInfo'):
            req=urllib.request.Request('https://api.telegram.org/bot'+cfg['token']+'/'+method,data=b'{}',headers={'Content-Type':'application/json'})
            try:
                with urllib.request.urlopen(req,timeout=10) as r:
                    data=json.load(r)
                result=data.get('result',{})
                print(method,'ok:',data.get('ok'))
                if method=='getMe': print('Bot username:',result.get('username'))
                else: print('Webhook configured:',bool(result.get('url')),'pending updates:',result.get('pending_update_count'))
            except urllib.error.HTTPError as e: print(method,'HTTP',e.code)
            except Exception as e: print(method,'failed',type(e).__name__)
    except Exception as e: print('Config check failed:',type(e).__name__)
PY
printf 'Diagnostics complete\n'
