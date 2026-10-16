#!/usr/bin/env bash
set -euo pipefail
cd /opt/atolin-assistant
test -z "$(git status --porcelain)"
backup="/etc/atolin-assistant/backups/report-memory-$(date -u +%Y%m%dT%H%M%SZ)"
install -d -m 700 "$backup"
cp server/reports.cjs server/index.cjs "$backup/"
git rev-parse HEAD > "$backup/previous-revision"
cp /etc/atolin-assistant/deployed-revision "$backup/deployed-revision"
bash server/deploy/update-atolin
test "$(git rev-parse HEAD)" = cf85b75a931fa7ff0e1a881872dfc0b6acbfc532
systemctl show atolin-assistant -p ActiveState -p NRestarts -p MemoryCurrent -p MemoryPeak -p MemoryMax
printf 'Deployed bounded report reader; original history and share files retained.\n'
