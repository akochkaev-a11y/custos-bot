#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
if [[ $EUID -ne 0 ]]; then
  echo 'Запусти: sudo bash install.sh'
  exit 1
fi
command -v python3 >/dev/null
python3 -m unittest discover -s tests -v
id custos >/dev/null 2>&1 || useradd --system --home /var/lib/custos --shell /usr/sbin/nologin custos
install -d -m 750 -o root -g custos /etc/custos
install -d -m 755 /opt/custos
install -m 644 custos.py /opt/custos/custos.py
install -m 644 deploy/custos.service /etc/systemd/system/custos.service
if [[ ! -f /etc/custos/config.json ]]; then
  python3 - <<'PY'
import getpass, json, os, pwd, secrets, urllib.request, urllib.error
token = getpass.getpass('Вставь токен Custos (ввод скрыт): ').strip()
try:
    request = urllib.request.Request('https://api.telegram.org/bot' + token + '/getMe', data=b'{}', headers={'Content-Type':'application/json'})
    with urllib.request.urlopen(request, timeout=20) as response:
        bot = json.load(response)['result']
    if bot.get('username') != 'custos_dialog_bot':
        raise ValueError('wrong bot')
except Exception:
    raise SystemExit('Не удалось проверить токен Custos. Настройка остановлена.') from None
code = secrets.token_urlsafe(18)
path = '/etc/custos/config.json'
fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o640)
with os.fdopen(fd,'w') as f:
    json.dump({'token':token, 'setup_code':code, 'data_dir':'/var/lib/custos'}, f)
os.chown(path, 0, pwd.getpwnam('custos').pw_gid)
PY
fi
systemctl daemon-reload
systemctl enable custos.service
systemctl restart custos.service
echo 'В личный чат с @custos_dialog_bot отправь команду:'
python3 - <<'PY'
import json
print('/start ' + json.load(open('/etc/custos/config.json'))['setup_code'])
PY
echo 'Проверка: systemctl status custos --no-pager'
