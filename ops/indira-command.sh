#!/usr/bin/env bash
set -uo pipefail
printf 'Telegram connectivity recheck\n'
curl -4 -sS -o /dev/null --connect-timeout 5 --max-time 8 -w 'Telegram HTTP=%{http_code}\n' https://api.telegram.org || true
printf 'Available connection tools\n'
for tool in wg openvpn tailscale sing-box xray; do command -v "$tool" >/dev/null && printf '%s installed\n' "$tool"; done
printf 'Tunnel interfaces\n'
ip -o link show | awk -F': ' '{print $2}' | sed 's/@.*//' | sort -u
printf 'Proxy settings present (values hidden)\n'
python3 - <<'PY'
import os
for k in os.environ:
 if k.lower().endswith('_proxy'):print(k+' configured')
from pathlib import Path
for p in ['/etc/wireguard','/etc/openvpn/client','/etc/sing-box','/usr/local/etc/xray']:
 d=Path(p)
 if d.is_dir(): print(p+': '+str(sum(1 for f in d.iterdir() if f.is_file()))+' configuration files')
PY
