#!/usr/bin/env bash
set -euo pipefail
/usr/local/bin/atolin-sync-download
python3 - <<'PY'
import json
from pathlib import Path
m=json.loads(Path('/var/lib/atolin-downloads/current/manifest.json').read_text())
assert m['versionCode']==103 and m['versionName']=='0.103'
assert m['sourceCommit']=='467018cabf6b79ea20e88321fc4f102f26632066'
assert m['sha256']=='25ab1f370f134cc0eb06f1f3430e5e06eeeb98391d22695de28c173ef65b23d7'
print('PUBLISHED_VERSION',m['versionName'],'VERSION_CODE',m['versionCode'],'SHA256',m['sha256'])
PY
temp_apk=$(mktemp /tmp/atolin-103-verify.XXXXXX)
trap 'rm -f "$temp_apk"' EXIT
curl --fail --silent --show-error --max-time 30 https://87.228.13.236/d/c915d17b1b8e072a/app.apk -o "$temp_apk"
digest=$(sha256sum "$temp_apk" | cut -d' ' -f1)
test "$digest" = 25ab1f370f134cc0eb06f1f3430e5e06eeeb98391d22695de28c173ef65b23d7
printf 'Public download matches verified 0.103 APK.\n'
systemctl is-active atolin-assistant nginx geostrategy geostrategy-apk
