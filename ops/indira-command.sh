#!/usr/bin/env bash
set -euo pipefail
umask 077
task_dir=/var/lib/atolin-build-106
source_sha=67cd0e2d6781f347a4d85e8a08dcf75727e32186
test "$(cat "$task_dir/ci/verified-source")" = "$source_sha"
test -s "$task_dir/ci/verified-106.apk"
export ANDROID_HOME=/var/lib/atolin-build-105/sdk
cd "$task_dir/source"
bash scripts/verify-apk.sh "$task_dir/ci/verified-106.apk" 106 0.106 > "$task_dir/publish-verify.log" 2>&1
git -C /opt/atolin-assistant fetch origin apk-download main > "$task_dir/publish-fetch.log" 2>&1
test "$(git -C /opt/atolin-assistant rev-parse "$source_sha^{tree}")" = "$(git -C /opt/atolin-assistant rev-parse origin/main^{tree})"
delivery_dir=$(mktemp -d "$task_dir/delivery.XXXXXX")
rmdir "$delivery_dir"
git -C /opt/atolin-assistant worktree add --detach "$delivery_dir" origin/apk-download > "$task_dir/worktree.log" 2>&1
cp "$task_dir/ci/verified-106.apk" "$delivery_dir/Atolin-Assistant.apk"
python3 - "$delivery_dir" "$source_sha" <<'PY'
import hashlib,json,sys
from pathlib import Path
root=Path(sys.argv[1]);data=(root/'Atolin-Assistant.apk').read_bytes()
manifest=dict(package='ru.atolin.assistant',versionCode=106,versionName='0.106',sha256=hashlib.sha256(data).hexdigest(),size=len(data),certificateSha256='4b69dd04a0bf31021e807f03f8fad980bf97ed81209b2e5f3916bbeb02aa0e0e',sourceCommit=sys.argv[2])
(root/'manifest.json').write_text(json.dumps(manifest)+'\n')
PY
git -C "$delivery_dir" add Atolin-Assistant.apk manifest.json
if ! git -C "$delivery_dir" diff --cached --quiet; then
  git -C "$delivery_dir" -c user.name='Atolin verified build' -c user.email='build@localhost' commit -m 'Verified APK 0.106: HTTP recovery and response diagnostics' > "$task_dir/delivery-commit.log" 2>&1
  git -C "$delivery_dir" push origin HEAD:apk-download > "$task_dir/push.log" 2>&1
fi
/usr/local/bin/atolin-sync-download > "$task_dir/sync.log" 2>&1
python3 - <<'PY'
import json,hashlib
from pathlib import Path
m=json.loads(Path('/var/lib/atolin-downloads/current/manifest.json').read_text())
assert m['versionCode']==106 and m['versionName']=='0.106'
assert m['sourceCommit']=='67cd0e2d6781f347a4d85e8a08dcf75727e32186'
print('VERIFIED_PUBLISHED_MANIFEST',json.dumps(m))
PY
temp_apk=$(mktemp /tmp/atolin-106-verify.XXXXXX)
trap 'rm -f "$temp_apk"' EXIT
curl --fail --silent --show-error --max-time 30 https://87.228.13.236/d/c915d17b1b8e072a/app.apk -o "$temp_apk"
test "$(sha256sum "$temp_apk" | cut -d' ' -f1)" = "$(sha256sum "$task_dir/ci/verified-106.apk" | cut -d' ' -f1)"
printf 'Public download matches verified 0.106 APK.\n'
systemctl is-active atolin-assistant nginx geostrategy geostrategy-apk
