#!/usr/bin/env bash
set -euo pipefail
umask 077
mkdir -p /var/lib/atolin-build-105
cat > /var/lib/atolin-build-105/build.sh <<'ATOLIN_BUILD_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
umask 077
task_dir=/var/lib/atolin-build-105
mkdir -p "$task_dir/work" "$task_dir/tools"
if ! git -C /opt/atolin-assistant fetch origin main apk-download >"$task_dir/fetch.log" 2>&1; then echo SOURCE_FETCH_FAILED; exit 1; fi
test "$(git -C /opt/atolin-assistant rev-parse origin/main)" = 8229e069a9dd592b062d4c5ad8027ae4718fe13f
git -C /opt/atolin-assistant archive 8229e069a9dd592b062d4c5ad8027ae4718fe13f | tar -x -C "$task_dir/work"
cd "$task_dir/tools"
if ! test -x gradle-8.11/bin/gradle; then
  curl --fail --silent --show-error --location --max-time 180 https://services.gradle.org/distributions/gradle-8.11-bin.zip -o gradle.zip
  curl --fail --silent --show-error --location --max-time 30 https://services.gradle.org/distributions/gradle-8.11-bin.zip.sha256 -o gradle.sha256
  printf '%s  gradle.zip\n' "$(cat gradle.sha256)" | sha256sum --check
  unzip -q -o gradle.zip
fi
export ANDROID_HOME="$task_dir/sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
if ! test -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager"; then
  curl --fail --silent --show-error --location --max-time 180 https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -o android.zip
  mkdir -p "$ANDROID_HOME/cmdline-tools"
  unzip -q -o android.zip -d "$ANDROID_HOME/cmdline-tools"
  mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
fi
set +o pipefail
yes | "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --licenses >/dev/null
set -o pipefail
"$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" "platforms;android-35" "build-tools;35.0.0"
cd "$task_dir/work"
python3 tests/report-storage.py
"$task_dir/tools/gradle-8.11/bin/gradle" --no-daemon --max-workers=1 -Dorg.gradle.jvmargs=-Xmx1024m clean assembleDebug signingReport
bash scripts/verify-apk.sh app/build/outputs/apk/debug/app-debug.apk 105 0.105
cp app/build/outputs/apk/debug/app-debug.apk "$task_dir/first.apk"
ANDROID_USER_HOME="$task_dir/fresh-android" "$task_dir/tools/gradle-8.11/bin/gradle" --no-daemon --max-workers=1 -Dorg.gradle.jvmargs=-Xmx1024m clean assembleDebug
bash scripts/verify-apk.sh app/build/outputs/apk/debug/app-debug.apk 105 0.105
python3 - <<'PY'
import hashlib,json
from pathlib import Path
root=Path('/var/lib/atolin-build-105')
apk=root/'work/app/build/outputs/apk/debug/app-debug.apk'
cert=(root/'work/app/signing-certificate.sha256').read_text().strip()
assert cert=='4b69dd04a0bf31021e807f03f8fad980bf97ed81209b2e5f3916bbeb02aa0e0e'
m=dict(package='ru.atolin.assistant',versionCode=105,versionName='0.105',sha256=hashlib.sha256(apk.read_bytes()).hexdigest(),size=apk.stat().st_size,certificateSha256=cert,sourceCommit='8229e069a9dd592b062d4c5ad8027ae4718fe13f')
(root/'manifest.json').write_text(json.dumps(m)+'\n')
print('VERIFIED_APK',m['versionName'],m['sha256'],m['size'])
PY
git -C /opt/atolin-assistant worktree add --detach "$task_dir/delivery" origin/apk-download >"$task_dir/worktree.log" 2>&1
cp app/build/outputs/apk/debug/app-debug.apk "$task_dir/delivery/Atolin-Assistant.apk"
cp "$task_dir/manifest.json" "$task_dir/delivery/manifest.json"
git -C "$task_dir/delivery" -c user.name='Atolin release' -c user.email='noreply@users.noreply.github.com' add Atolin-Assistant.apk manifest.json
git -C "$task_dir/delivery" -c user.name='Atolin release' -c user.email='noreply@users.noreply.github.com' commit -m 'Verified APK 0.105'
if ! git -C "$task_dir/delivery" push origin HEAD:refs/heads/apk-download >"$task_dir/push.log" 2>&1; then echo DELIVERY_PUSH_FAILED; exit 1; fi
/usr/local/bin/atolin-sync-download
python3 - <<'PY'
import json
from pathlib import Path
m=json.loads(Path('/var/lib/atolin-downloads/current/manifest.json').read_text())
assert m['versionCode']==105 and m['sourceCommit']=='8229e069a9dd592b062d4c5ad8027ae4718fe13f'
print('PUBLISHED_VERSION',m['versionName'],'SHA256',m['sha256'])
PY
systemctl is-active atolin-assistant nginx geostrategy geostrategy-apk
echo RELEASE_105_COMPLETE
ATOLIN_BUILD_SCRIPT
systemd-run --unit=atolin-build-105 --property=MemoryMax=2G --property=CPUQuota=150% --property=Nice=10 /bin/bash -c 'exec /bin/bash /var/lib/atolin-build-105/build.sh > /var/lib/atolin-build-105/build.log 2>&1'
printf 'Verified-source release build started with resource limits.\n'
