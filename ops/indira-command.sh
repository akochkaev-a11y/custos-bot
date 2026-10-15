#!/usr/bin/env bash
set -euo pipefail
printf 'Indira SSH connection verified\n'
date -u '+UTC %Y-%m-%d %H:%M:%S'
nproc
uptime
free -h
df -h /
for unit in atolin-assistant geostrategy geostrategy-apk custos; do
  printf '%s: ' "$unit"
  systemctl is-active "$unit" || true
done
