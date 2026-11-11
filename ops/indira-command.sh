#!/usr/bin/env bash
set -euo pipefail
umask 077
printf 'Custos detailed network diagnosis 2026-11-11\n'
date -u
printf '\nAddresses and Telegram route\n'
ip -brief address
ip route get 149.154.166.110
ip rule show
printf '\nIPv4 firewall\n'
if command -v iptables >/dev/null; then iptables -S; iptables -t nat -S; fi
if command -v ufw >/dev/null; then ufw status verbose; fi
printf '\nOther firewall tables\n'
if command -v nft >/dev/null; then nft list ruleset; fi
printf '\nIPv6 routing\n'
ip -6 route show
printf '\nHost overrides\n'
python3 - <<'PY'
from pathlib import Path
for line in Path('/etc/hosts').read_text().splitlines():
    if 'telegram' in line.lower(): print(line)
PY
printf '\nTCP header capture during probes\n'
capture_pid=''
if command -v tcpdump >/dev/null; then
  timeout 18 tcpdump -nn -l -i any -c 16 'host 149.154.166.110 and tcp and (port 443 or port 80)' 2>&1 &
  capture_pid=$!
fi
python3 -u - <<'PY'
import concurrent.futures,socket,ssl,time,urllib.request,urllib.error,json
def request(host):
    t=time.monotonic()
    try:
        with urllib.request.urlopen('https://'+host,timeout=7) as r:
            print('HTTPS',host,r.status,round(time.monotonic()-t,2),flush=True)
    except urllib.error.HTTPError as e: print('HTTPS',host,e.code,round(time.monotonic()-t,2),flush=True)
    except Exception as e: print('HTTPS',host,type(e).__name__,str(getattr(e,'reason',''))[:140],round(time.monotonic()-t,2),flush=True)
hosts=['api.telegram.org','telegram.org','core.telegram.org','github.com','www.apple.com']
with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:list(pool.map(request,hosts))
for resolver in ['https://dns.google/resolve?name=api.telegram.org&type=A&edns_client_subnet=8.8.8.0/24','https://cloudflare-dns.com/dns-query?name=api.telegram.org&type=A']:
    try:
        req=urllib.request.Request(resolver,headers={'Accept':'application/dns-json'})
        with urllib.request.urlopen(req,timeout=5) as r:data=json.load(r)
        print('Independent DNS',resolver.split('/')[2],[a['data'] for a in data.get('Answer',[]) if a['type']==1],flush=True)
    except Exception as e:print('DNS resolver check',type(e).__name__)
print('Available network tools:',flush=True)
import shutil
for tool in ('traceroute','tracepath','mtr','tcpdump','curl','openssl'):print(tool,bool(shutil.which(tool)),flush=True)
PY
if test -n "$capture_pid"; then wait "$capture_pid" || true; fi
printf '\nCustos service network restrictions\n'
systemctl show custos.service -p IPAddressDeny -p IPAddressAllow -p RestrictAddressFamilies -p PrivateNetwork --no-pager
printf 'Detailed diagnosis complete\n'
