#!/usr/bin/env bash
set -uo pipefail
cd /opt/atolin-assistant
git status --porcelain
git ls-files server/test server/deploy '*AGENTS.md'
systemctl show atolin-assistant -p FragmentPath -p DropInPaths -p User -p Group
