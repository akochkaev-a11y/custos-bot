#!/usr/bin/env bash
set -euo pipefail
/usr/local/bin/atolin-sync-download
python3 - <<'PY'
import json
from pathlib import Path
m=json.loads(Path('/var/lib/atolin-downloads/current/manifest.json').read_text())
assert m['versionCode']==104 and m['versionName']=='0.104'
assert m['sourceCommit']=='178146943489d67d4942152a1e36420d0c82f444'
assert m['sha256']=='494839a62816ecaed7c03153ac88d92c053303c4e52037881f9aeb885723984d'
assert m['certificateSha256']=='4b69dd04a0bf31021e807f03f8fad980bf97ed81209b2e5f3916bbeb02aa0e0e'
print('PUBLISHED_VERSION',m['versionName'],'VERSION_CODE',m['versionCode'],'SHA256',m['sha256'])
PY
temp_apk=$(mktemp /tmp/atolin-104-verify.XXXXXX)
trap 'rm -f "$temp_apk"' EXIT
curl --fail --silent --show-error --max-time 30 https://87.228.13.236/d/c915d17b1b8e072a/app.apk -o "$temp_apk"
digest=$(sha256sum "$temp_apk" | cut -d' ' -f1)
test "$digest" = 494839a62816ecaed7c03153ac88d92c053303c4e52037881f9aeb885723984d
printf 'Public download matches verified 0.104 APK.\n'
systemctl is-active atolin-assistant nginx geostrategy geostrategy-apk
