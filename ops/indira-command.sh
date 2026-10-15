#!/usr/bin/env bash
set -uo pipefail
python3 - <<'PY'
import socket
for h in ('api.telegram.org','telegram.org'):
    try: print(h, sorted({str(x[4][0]) for x in socket.getaddrinfo(h,443)}))
    except Exception as e: print(h,type(e).__name__)
PY
for fam in -4 -6; do
  printf 'Telegram HTTPS %s: ' "$fam"
  curl "$fam" -sS -o /dev/null --connect-timeout 5 --max-time 8 -w 'http=%{http_code} ip=%{remote_ip}\n' https://api.telegram.org || true
done
printf 'GitHub HTTPS: '
curl -4 -sS -o /dev/null --connect-timeout 5 --max-time 8 -w 'http=%{http_code}\n' https://github.com || true
