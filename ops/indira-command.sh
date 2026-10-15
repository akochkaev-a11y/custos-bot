#!/usr/bin/env bash
set -uo pipefail
curl -sS --connect-timeout 5 --max-time 8 -H 'accept: application/dns-json' 'https://cloudflare-dns.com/dns-query?name=api.telegram.org&type=A'
printf '\n'
for ip in 149.154.167.220 149.154.167.99; do
  printf 'TLS api.telegram.org via %s: ' "$ip"
  curl -4 -sS --resolve "api.telegram.org:443:$ip" -o /dev/null --connect-timeout 4 --max-time 6 -w 'http=%{http_code}\n' https://api.telegram.org || true
done
