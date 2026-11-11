#!/usr/bin/env bash
set -euo pipefail
printf 'Checking existing local listener for Custos connectivity\n'
python3 -u - <<'PY'
import urllib.request,urllib.error,socket
opener=urllib.request.build_opener(urllib.request.ProxyHandler({'https':'http://127.0.0.1:8080'}))
try:
    with opener.open('https://api.telegram.org',timeout=8) as r:
        print('Existing listener HTTPS tunnel verified; Telegram HTTP',r.status)
except urllib.error.HTTPError as e:print('Existing listener returned HTTP',e.code)
except urllib.error.URLError as e:
    print('Existing listener tunnel failed:',str(e.reason).splitlines()[0][:180])
except Exception as e: print('Existing listener check failed:',type(e).__name__)
PY
ss -H -ltnp 'sport = :8080'
printf 'Listener check complete\n'
