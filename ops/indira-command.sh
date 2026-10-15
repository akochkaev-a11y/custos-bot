#!/usr/bin/env bash
set -uo pipefail
printf 'OUTPUT policy and rules\n'
iptables -S OUTPUT 2>/dev/null || true
nft list ruleset 2>/dev/null | head -100 || true
printf 'Routes\n'
ip route get 149.154.166.110
printf 'TCP reachability\n'
python3 - <<'PY'
import socket
for host,port in [('149.154.166.110',443),('149.154.166.110',80),('api.telegram.org',443),('github.com',443)]:
 try:
  s=socket.create_connection((host,port),4);s.close();print(host,port,'OK')
 except OSError as e: print(host,port,type(e).__name__)
PY
