#!/usr/bin/env bash
set -euo pipefail
umask 077
printf 'Custos IPv4 route comparison 2026-11-11\n'
date -u
printf '\nTelegram IPv4 HTTPS (no bot token)\n'
curl -4 -I --noproxy '*' --connect-timeout 8 --max-time 10 -sS -w '\nHTTP=%{http_code} remote=%{remote_ip} connect=%{time_connect} tls=%{time_appconnect}\n' https://api.telegram.org || true
printf '\nParallel TCP traceroutes (port 443, maximum 20 hops)\n'
timeout 25 traceroute -4 -n -T -p 443 -q 1 -w 1 -m 20 api.telegram.org > /tmp/custos-trace-telegram.txt 2>&1 &
tg=$!
timeout 25 traceroute -4 -n -T -p 443 -q 1 -w 1 -m 20 github.com > /tmp/custos-trace-control.txt 2>&1 &
control=$!
wait "$tg" || true
wait "$control" || true
printf '\nTelegram trace\n'
cat /tmp/custos-trace-telegram.txt
printf '\nGitHub control trace\n'
cat /tmp/custos-trace-control.txt
printf '\nRaw TCP comparison to API and Telegram web\n'
python3 -u - <<'PY'
import socket,concurrent.futures,time
def probe(host):
    infos=socket.getaddrinfo(host,443,socket.AF_INET,socket.SOCK_STREAM)
    ip=infos[0][4][0]
    start=time.monotonic()
    try:
        with socket.create_connection((ip,443),timeout=5):
            print(host,ip,'TCP connected',round(time.monotonic()-start,2),flush=True)
    except Exception as e: print(host,ip,type(e).__name__,round(time.monotonic()-start,2),flush=True)
with concurrent.futures.ThreadPoolExecutor(max_workers=5) as pool:
    list(pool.map(probe,['api.telegram.org','telegram.org','core.telegram.org','web.telegram.org','github.com']))
PY
printf 'Route diagnosis complete\n'
