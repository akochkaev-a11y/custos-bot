#!/usr/bin/env bash
set -euo pipefail
umask 077
task_dir=/var/lib/atolin-build-108
source_sha=36577a93a08b0f2cae535ef3a732062b76b03aa5
test "$(cat "$task_dir/ci/verified-source")" = "$source_sha"
test -s "$task_dir/ci/verified-108.apk"
export ANDROID_HOME=/var/lib/atolin-build-105/sdk
git -C /opt/atolin-assistant fetch origin main fix/startup-history-108 apk-download > "$task_dir/publish-fetch.log" 2>&1
if test ! -d "$task_dir/source"; then
  git -C /opt/atolin-assistant worktree add --detach "$task_dir/source" "$source_sha" > "$task_dir/source-worktree.log" 2>&1
fi
test "$(git -C "$task_dir/source" rev-parse HEAD)" = "$source_sha"
cd "$task_dir/source"
bash scripts/verify-apk.sh "$task_dir/ci/verified-108.apk" 108 0.108 > "$task_dir/publish-verify.log" 2>&1
git -C /opt/atolin-assistant fetch origin apk-download main > "$task_dir/publish-fetch.log" 2>&1
test "$(git -C /opt/atolin-assistant rev-parse "$source_sha^{tree}")" = "$(git -C /opt/atolin-assistant rev-parse origin/main^{tree})"
python3 - <<'PY'
import json,subprocess
raw=subprocess.check_output(['git','-C','/opt/atolin-assistant','show','origin/apk-download:manifest.json'],text=True)
manifest=json.loads(raw)
assert manifest['versionCode']<108, 'Version 108 already published; do not replace APK bytes under the same code'
PY
delivery_dir=$(mktemp -d "$task_dir/delivery.XXXXXX")
rmdir "$delivery_dir"
git -C /opt/atolin-assistant worktree add --detach "$delivery_dir" origin/apk-download > "$task_dir/worktree.log" 2>&1
cp "$task_dir/ci/verified-108.apk" "$delivery_dir/Atolin-Assistant.apk"
python3 - "$delivery_dir" "$source_sha" <<'PY'
import hashlib,json,sys
from pathlib import Path
root=Path(sys.argv[1]);data=(root/'Atolin-Assistant.apk').read_bytes()
manifest=dict(package='ru.atolin.assistant',versionCode=108,versionName='0.108',sha256=hashlib.sha256(data).hexdigest(),size=len(data),certificateSha256='4b69dd04a0bf31021e807f03f8fad980bf97ed81209b2e5f3916bbeb02aa0e0e',sourceCommit=sys.argv[2])
(root/'manifest.json').write_text(json.dumps(manifest)+'\n')
PY
git -C "$delivery_dir" add Atolin-Assistant.apk manifest.json
if ! git -C "$delivery_dir" diff --cached --quiet; then
  git -C "$delivery_dir" -c user.name='Atolin verified build' -c user.email='build@localhost' commit -m 'Verified APK 0.108: background startup recovery' > "$task_dir/delivery-commit.log" 2>&1
  git -C "$delivery_dir" push origin HEAD:apk-download > "$task_dir/push.log" 2>&1
fi
/usr/local/bin/atolin-sync-download > "$task_dir/sync.log" 2>&1
python3 - <<'PY'
import json,hashlib
from pathlib import Path
m=json.loads(Path('/var/lib/atolin-downloads/current/manifest.json').read_text())
assert m['versionCode']==108 and m['versionName']=='0.108'
assert m['sourceCommit']=='36577a93a08b0f2cae535ef3a732062b76b03aa5'
print('VERIFIED_PUBLISHED_MANIFEST',json.dumps(m))
PY
temp_apk=$(mktemp /tmp/atolin-108-verify.XXXXXX)
trap 'rm -f "$temp_apk"' EXIT
curl --fail --silent --show-error --max-time 30 'https://87.228.13.236/d/c915d17b1b8e072a/app.apk?v=108' -o "$temp_apk"
test "$(sha256sum "$temp_apk" | cut -d' ' -f1)" = "$(sha256sum "$task_dir/ci/verified-108.apk" | cut -d' ' -f1)"
printf 'Public download matches verified 0.108 APK.\n'
systemctl is-active atolin-assistant nginx geostrategy geostrategy-apk
