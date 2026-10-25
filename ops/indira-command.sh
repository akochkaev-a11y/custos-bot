#!/usr/bin/env bash
set -euo pipefail
umask 077
task_dir=/var/lib/atolin-build-106
mkdir -p "$task_dir"
git -C /opt/atolin-assistant fetch origin fix/http-search-recovery-106 >"$task_dir/fetch.log" 2>&1
test "$(git -C /opt/atolin-assistant rev-parse FETCH_HEAD)" = 7bf20caf46777ed90cabf7fb035a58d0f52fcc14
mkdir -p "$task_dir/source"
git -C /opt/atolin-assistant archive 7bf20caf46777ed90cabf7fb035a58d0f52fcc14 | tar -x -C "$task_dir/source"
python3 - <<'PY'
from pathlib import Path
root=Path('/var/lib/atolin-build-105')
for path in sorted(root.glob('*')):
 print('BUILD_RESOURCE',path.name,'directory' if path.is_dir() else 'file')
script=root/'build.sh'
if script.exists():
 import re
 text=script.read_text()
 for line in text.splitlines():
  if re.match(r'(export (ANDROID|JAVA|GRADLE)|.*gradle.*assemble|.*publish-download|.*verify-apk)',line) and not re.search(r'(?i)token|password|secret',line):
   print('BUILD_COMMAND',line[:300])
PY
mkdir -p "$task_dir/test-classes"
cd "$task_dir/source"
javac -d "$task_dir/test-classes" app/src/main/java/ru/atolin/assistant/WorkSession.java tests/WorkSessionTest.java app/src/main/java/ru/atolin/assistant/HttpRecoveryPolicy.java app/src/main/java/ru/atolin/assistant/HttpFailureEvidence.java tests/HttpRecoveryTest.java
java -cp "$task_dir/test-classes" ru.atolin.assistant.WorkSessionTest
java -cp "$task_dir/test-classes" ru.atolin.assistant.HttpRecoveryTest
systemctl is-active atolin-assistant nginx geostrategy geostrategy-apk
