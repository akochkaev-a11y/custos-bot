#!/usr/bin/env bash
set -euo pipefail
systemctl show atolin-build-105 -p ActiveState -p SubState -p Result -p ExecMainStatus
python3 - <<'PY'
from pathlib import Path
p=Path('/var/lib/atolin-build-105/build.log')
if p.exists():
    data=p.read_bytes()[-24000:].decode('utf-8','replace')
    rows=[line for line in data.replace('\r','\n').splitlines() if any(word in line for word in ['BUILD SUCCESSFUL','FAILURE:','FAILED','Exception','error:','What went wrong','Could not','VERIFIED_APK','PUBLISHED_VERSION','RELEASE_105_COMPLETE','gradle.zip: OK','> Task','Downloading','Installed','done.'])]
    print('\n'.join(rows[-30:]))
PY
systemctl is-active atolin-assistant nginx geostrategy geostrategy-apk
