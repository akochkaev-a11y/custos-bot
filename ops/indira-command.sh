#!/usr/bin/env bash
set -euo pipefail
printf 'BUILD_HOST_CAPACITY\n'
free -m
df -h / /opt
for tool in java javac gradle sdkmanager apksigner; do command -v "$tool" || true; done
for location in /opt/android-sdk /opt/android /usr/local/lib/android/sdk /opt/gradle /root/.gradle/caches /opt/game; do
  if test -d "$location"; then printf 'AVAILABLE %s\n' "$location"; fi
done
find /opt -maxdepth 3 -type f -name gradle -print 2>/dev/null
git -C /opt/atolin-assistant rev-parse HEAD
systemctl is-active atolin-assistant nginx geostrategy geostrategy-apk
