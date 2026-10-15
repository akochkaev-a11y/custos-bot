#!/usr/bin/env python3
"""Read token over SSH stdin. Verify account ownership without logging credentials."""
import json
import os
from pathlib import Path
import pwd
import secrets
import sqlite3
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from custos import API, APIError, Custos, UPDATES


def verified_owner(updates, api):
    starts = {u['message']['from']['id'] for u in updates if 'message' in u
              and u['message']['chat']['type'] == 'private'
              and u['message'].get('text','').startswith('/start')
              and not u['message']['from'].get('is_bot')}
    connected = set()
    for u in updates:
        info = u.get('business_connection')
        if info and info.get('is_enabled'):
            connected.add(info['user']['id'])
        for field in ('business_message', 'edited_business_message'):
            m = u.get(field)
            if m:
                info = api.call('getBusinessConnection', business_connection_id=m['business_connection_id'])
                if info.get('is_enabled'):
                    connected.add(info['user']['id'])
    matched = starts & connected
    if len(matched) != 1:
        raise ValueError('Owner cannot be verified; send /start and reconnect chat automation')
    return matched.pop()


def main():
    os.umask(0o077)
    token = sys.stdin.read().strip()
    if not token:
        raise ValueError('CUSTOS_BOT_TOKEN missing')
    api = API(token)
    me = api.call('getMe')
    if me.get('username') != 'custos_dialog_bot':
        raise ValueError('Token belongs to a different bot')
    if api.call('getWebhookInfo').get('url'):
        raise ValueError('Existing webhook must be reviewed first')
    config_path = Path('/etc/custos/config.json')
    config = json.loads(config_path.read_text()) if config_path.exists() else {}
    owner = 0
    db_path = Path('/var/lib/custos/archive.sqlite3')
    if db_path.exists():
        with sqlite3.connect(db_path) as db:
            row = db.execute("SELECT value FROM meta WHERE key='owner'").fetchone()
            owner = int(row[0]) if row else 0
    updates = []
    if not owner:
        updates = api.call('getUpdates', timeout=0, limit=100, allowed_updates=UPDATES)
        owner = verified_owner(updates, api)
    config.update(token=token, setup_code=config.get('setup_code') or secrets.token_urlsafe(18),
                  data_dir='/var/lib/custos')
    temporary = config_path.with_suffix('.tmp')
    temporary.write_text(json.dumps(config))
    group = pwd.getpwnam('custos')
    temporary.chmod(0o640)
    os.chown(temporary, 0, group.pw_gid)
    temporary.replace(config_path)
    bot = Custos('/var/lib/custos', api, config['setup_code'])
    with bot.db:
        bot.set('owner',owner)
    # Persist the exact retrieved batch before normal polling acknowledges updates.
    bot.ingest(updates)
    bot.db.close()
    for path in Path('/var/lib/custos').rglob('*'):
        if not path.is_symlink():
            os.chown(path, group.pw_uid, group.pw_gid)
    print('Custos token and Telegram account verified; configuration saved')


if __name__ == '__main__':
    try:
        main()
    except APIError as e:
        raise SystemExit(f'Telegram validation failed: code={e.code}') from None
    except ValueError as e:
        raise SystemExit(str(e)) from None
