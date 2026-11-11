#!/usr/bin/env bash
set -euo pipefail
printf 'Custos network diagnostics\n'
python3 -u - <<'PY'
import socket,ssl,concurrent.futures,urllib.request,json
from pathlib import Path
print('Proxy configured:',bool(urllib.request.getproxies()),flush=True)
ips=sorted({(x[0],x[4][0]) for x in socket.getaddrinfo('api.telegram.org',443,type=socket.SOCK_STREAM)})
def probe(item):
    family,ip=item
    for port in (443,80):
        s=socket.socket(family,socket.SOCK_STREAM);s.settimeout(5)
        try:
            s.connect((ip,port))
            print('TCP',ip,port,'OK',flush=True)
            if port==443:
                with ssl.create_default_context().wrap_socket(s,server_hostname='api.telegram.org') as tls:
                    print('TLS verified',ip,tls.version(),flush=True)
        except Exception as e: print('Connect',ip,port,type(e).__name__,flush=True)
        finally:s.close()
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:list(pool.map(probe,ips))
for p in ('/etc/custos','/var/lib/custos'):
    root=Path(p)
    print(p,'exists:',root.exists())
    if root.exists(): print('Names:',','.join(x.name for x in root.iterdir()))
PY
ip -brief link
printf 'Proxy listener checks\n'
for port in 1080 10808 7890 8080 3128; do
  if ss -H -ltn "sport = :$port" | head -1 | rg -q .; then printf 'Local proxy candidate port %s\n' "$port"; fi
done
printf 'Done\n'
