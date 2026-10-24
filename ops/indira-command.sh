#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
import json
from pathlib import Path
m=json.loads(Path('/var/lib/atolin-downloads/current/manifest.json').read_text())
assert m['versionCode']==105 and m['versionName']=='0.105'
assert m['sourceCommit']=='8229e069a9dd592b062d4c5ad8027ae4718fe13f'
assert m['sha256']=='719e2751cafa33874c3faea79afa64e6f510b889a097e42d2ccfc85573c17f18'
assert m['certificateSha256']=='4b69dd04a0bf31021e807f03f8fad980bf97ed81209b2e5f3916bbeb02aa0e0e'
print('PUBLISHED_VERSION',m['versionName'],'VERSION_CODE',m['versionCode'],'SHA256',m['sha256'])
PY
temp_apk=$(mktemp /tmp/atolin-105-verify.XXXXXX)
trap 'rm -f "$temp_apk"' EXIT
curl --fail --silent --show-error --max-time 30 https://87.228.13.236/d/c915d17b1b8e072a/app.apk -o "$temp_apk"
digest=$(sha256sum "$temp_apk" | cut -d' ' -f1)
test "$digest" = 719e2751cafa33874c3faea79afa64e6f510b889a097e42d2ccfc85573c17f18
printf 'Public download matches verified 0.105 APK.\n'
systemctl is-active atolin-assistant nginx geostrategy geostrategy-apk
