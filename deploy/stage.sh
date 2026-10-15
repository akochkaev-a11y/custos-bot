#!/usr/bin/env bash
set -euo pipefail
test "$(id -u)" -eq 0
cd -- "$(dirname -- "$0")/.."
python3 -m unittest discover -s tests -v
python3 -m py_compile custos.py deploy/configure.py
id custos >/dev/null 2>&1 || useradd --system --home /var/lib/custos --shell /usr/sbin/nologin custos
install -d -m 750 -o root -g custos /etc/custos
install -d -m 755 /opt/custos /opt/custos/deploy
install -d -m 700 -o custos -g custos /var/lib/custos
systemctl stop custos.service 2>/dev/null || true
install -m 644 custos.py /opt/custos/custos.py
install -m 644 deploy/configure.py /opt/custos/deploy/configure.py
install -m 644 deploy/custos.service /etc/systemd/system/custos.service
systemctl daemon-reload
echo 'Custos program staged'
