#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
from pathlib import Path
import re
p=Path('/var/lib/atolin-build-106/ci/build.log')
if not p.exists():
 print('BUILD_LOG_PENDING')
else:
 lines=p.read_text(errors='replace').splitlines()
 for i,line in enumerate(lines):
  if re.search(r'error:|^FAILURE:|^\* What went wrong:|^Execution failed|^> |^BUILD FAILED|^Could not |^SDK location|^License|^Unable to ',line):
   print('BUILD_DIAGNOSTIC',line[:500])
PY
