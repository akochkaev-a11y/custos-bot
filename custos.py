#!/usr/bin/env python3
"""Custos 0.2 - private Telegram Business archive. Python 3.12, stdlib only."""
import hashlib
import hmac
import json
import logging
import os
from pathlib import Path
import secrets
import shutil
import signal
import sqlite3
import time
import urllib.error
import urllib.request

LOG = logging.getLogger('custos')
UPDATES = ['message', 'business_connection', 'business_message',
           'edited_business_message', 'deleted_business_messages']
MEDIA = {'photo': 'sendPhoto', 'video': 'sendVideo', 'document': 'sendDocument',
         'audio': 'sendAudio', 'voice': 'sendVoice', 'video_note': 'sendVideoNote',
         'animation': 'sendAnimation', 'sticker': 'sendSticker'}


class APIError(Exception):
    def __init__(self, code, delay=0):
        super().__init__(f'Telegram API code {code}')
        self.code, self.delay = code, delay


class API:
    def __init__(self, token):
        self.base = 'https://api.telegram.org/bot' + token + '/'
        self.files = 'https://api.telegram.org/file/bot' + token + '/'

    def call(self, method, upload=None, **params):
        if upload:
            field, path = upload
            boundary = secrets.token_hex(20)
            body = bytearray()
            for key, value in params.items():
                body.extend((f'--{boundary}\r\nContent-Disposition: form-data; '
                             f'name="{key}"\r\n\r\n{value}\r\n').encode())
            body.extend((f'--{boundary}\r\nContent-Disposition: form-data; '
                         f'name="{field}"; filename="attachment.bin"\r\n'
                         'Content-Type: application/octet-stream\r\n\r\n').encode())
            body.extend(Path(path).read_bytes())
            body.extend(f'\r\n--{boundary}--\r\n'.encode())
            content_type = f'multipart/form-data; boundary={boundary}'
        else:
            body = json.dumps(params).encode()
            content_type = 'application/json'
        req = urllib.request.Request(self.base + method, data=body,
                                     headers={'Content-Type': content_type})
        try:
            with urllib.request.urlopen(req, timeout=65) as response:
                data = json.load(response)
        except urllib.error.HTTPError as error:
            try:
                data = json.load(error)
            except (ValueError, OSError):
                raise APIError(error.code) from None
        except (OSError, ValueError):
            # Never log exceptions containing an API URL/token or message body.
            raise APIError(0) from None
        if not data.get('ok'):
            raise APIError(data.get('error_code', 0),
                           data.get('parameters', {}).get('retry_after', 0))
        return data['result']

    def download(self, file_id, dest, limit):
        info = self.call('getFile', file_id=file_id)
        if info.get('file_size', 0) > limit:
            raise APIError(413)
        total = 0
        partial = dest.with_suffix('.part')
        try:
            with urllib.request.urlopen(self.files + info['file_path'], timeout=60) as r:
                with partial.open('wb') as f:
                    while chunk := r.read(65536):
                        total += len(chunk)
                        if total > limit:
                            raise APIError(413)
                        f.write(chunk)
            partial.replace(dest)
        except (OSError, ValueError):
            raise APIError(0) from None
        finally:
            partial.unlink(missing_ok=True)


def attachment(message):
    for kind in MEDIA:
        item = message.get(kind)
        if item:
            return kind, item[-1] if kind == 'photo' else item
    return None, None


def signature(message):
    kind, media = attachment(message)
    return json.dumps([message.get('text'), message.get('caption'), kind,
                       (media or {}).get('file_unique_id', (media or {}).get('file_id')),
                       message.get('entities'), message.get('caption_entities')], sort_keys=True)


def describe(message):
    author = message.get('from', {})
    name = ' '.join(filter(None, [author.get('first_name'), author.get('last_name')]))
    stamp = time.strftime('%d.%m.%Y %H:%M:%S', time.gmtime(message.get('date', 0) + 10800))
    kind, _ = attachment(message)
    return (f"Автор: {name or author.get('id', '?')}\n"
            f"Чат: {message['chat']['id']} | Сообщение: {message['message_id']}\n"
            f"Время: {stamp} МСК\n"
            f"{message.get('text') or message.get('caption') or ('Вложение: ' + (kind or 'неподдерживаемое'))}")


class Custos:
    def __init__(self, directory, api, setup_code, quota=2*1024**3):
        self.root = Path(directory)
        self.root.mkdir(parents=True, exist_ok=True)
        self.media = self.root / 'media'
        self.media.mkdir(exist_ok=True)
        self.db = sqlite3.connect(self.root / 'archive.sqlite3')
        self.db.execute('PRAGMA journal_mode=WAL')
        self.db.executescript('''
          CREATE TABLE IF NOT EXISTS meta(key TEXT PRIMARY KEY,value TEXT);
          CREATE TABLE IF NOT EXISTS inbox(id INTEGER PRIMARY KEY,body TEXT,done INTEGER DEFAULT 0);
          CREATE TABLE IF NOT EXISTS connections(id TEXT PRIMARY KEY,enabled INTEGER);
          CREATE TABLE IF NOT EXISTS messages(conn TEXT,chat INTEGER,id INTEGER,body TEXT,
            PRIMARY KEY(conn,chat,id));
          CREATE TABLE IF NOT EXISTS versions(conn TEXT,chat INTEGER,id INTEGER,hash TEXT,body TEXT,
            PRIMARY KEY(conn,chat,id,hash));
          CREATE TABLE IF NOT EXISTS outbox(key TEXT PRIMARY KEY,body TEXT,done INTEGER DEFAULT 0,
            attempts INTEGER DEFAULT 0,next_try REAL DEFAULT 0);
          CREATE TABLE IF NOT EXISTS files(id TEXT PRIMARY KEY,path TEXT,state TEXT,
            attempts INTEGER DEFAULT 0,next_try REAL DEFAULT 0);
        ''')
        self.api, self.code, self.quota = api, setup_code, quota

    def get(self, key, default='0'):
        row = self.db.execute('SELECT value FROM meta WHERE key=?', (key,)).fetchone()
        return row[0] if row else default

    def set(self, key, value):
        self.db.execute('INSERT OR REPLACE INTO meta VALUES(?,?)', (key, str(value)))

    def ingest(self, updates):
        with self.db:
            for update in updates:
                self.db.execute('INSERT OR IGNORE INTO inbox(id,body) VALUES(?,?)',
                                (update['update_id'], json.dumps(update)))
            if updates:
                self.set('offset', max(u['update_id'] for u in updates) + 1)

    def enqueue(self, key, text=None, message=None):
        # Telegram text limit is UTF-16 code units; use conservative chunks.
        if text:
            for index in range(0, len(text), 1800):
                body = json.dumps({'text': text[index:index+1800]})
                self.db.execute('INSERT OR IGNORE INTO outbox(key,body) VALUES(?,?)',
                                (f'{key}:text:{index}', body))
        if message and attachment(message)[0]:
            self.db.execute('INSERT OR IGNORE INTO outbox(key,body) VALUES(?,?)',
                            (key + ':media', json.dumps({'message': message})))

    def save(self, conn, m):
        key = (conn, m['chat']['id'], m['message_id'])
        digest = hashlib.sha256(signature(m).encode()).hexdigest()
        body = json.dumps(m)
        self.db.execute('INSERT OR IGNORE INTO versions VALUES(?,?,?,?,?)', (*key,digest,body))
        self.db.execute('INSERT OR REPLACE INTO messages VALUES(?,?,?,?)', (*key,body))

    def connection(self, conn):
        row = self.db.execute('SELECT enabled FROM connections WHERE id=?', (conn,)).fetchone()
        if row:
            return bool(row[0])
        info = self.api.call('getBusinessConnection', business_connection_id=conn)
        if info['user']['id'] != int(self.get('owner')):
            return False
        self.db.execute('INSERT OR REPLACE INTO connections VALUES(?,?)', (conn, int(info['is_enabled'])))
        return info['is_enabled']

    def process(self):
        # Pairing messages can arrive after business updates. Handle pairing first.
        rows = self.db.execute('SELECT id,body FROM inbox WHERE done=0 ORDER BY id').fetchall()
        rows.sort(key=lambda row: 'message' not in json.loads(row[1]))
        for uid, raw in rows:
            update = json.loads(raw)
            if not int(self.get('owner')) and 'message' not in update:
                continue
            with self.db:
                self.handle(uid, update)
                self.db.execute('UPDATE inbox SET done=1 WHERE id=?', (uid,))
        with self.db:
            self.db.execute('DELETE FROM inbox WHERE done=1')

    def handle(self, uid, u):
        owner = int(self.get('owner'))
        if 'message' in u:
            m = u['message']
            if m['chat']['type'] != 'private' or m.get('from', {}).get('is_bot'):
                return
            sender = m.get('from', {}).get('id')
            if not owner:
                supplied = m.get('text', '').partition(' ')[2].strip()
                if not supplied or not hmac.compare_digest(supplied, self.code):
                    return
                owner = sender
                self.set('owner', owner)
            if sender != owner:
                return
            text = m.get('text','')
            if text.startswith('/start'):
                self.enqueue(str(uid), 'Custos подключён. Отслеживаю новые сообщения в разрешённых чатах. '
                             'Копии новых сообщений, удаления и правки отправляю сюда. /status - состояние. '
                             'Ответ на сообщение в выбранном чате - запрос копии доступного вложения.')
            elif text == '/status':
                count = self.db.execute('SELECT count(*) FROM messages').fetchone()[0]
                pending = self.db.execute('SELECT count(*) FROM outbox WHERE done=0').fetchone()[0]
                active = self.db.execute('SELECT count(*) FROM connections WHERE enabled=1').fetchone()[0]
                self.enqueue(str(uid), f'Custos 0.2\nСоединений: {active}\nСообщений: {count}\n'
                             f'Уведомлений в очереди: {pending}\n'
                             f'Свободно на диске: {shutil.disk_usage(self.root).free//1024**2} МиБ')
            return
        if 'business_connection' in u:
            info = u['business_connection']
            if info['user']['id'] != owner:
                return
            self.db.execute('INSERT OR REPLACE INTO connections VALUES(?,?)',
                            (info['id'], int(info['is_enabled'])))
            self.enqueue(str(uid), 'Автоматизация Custos ' + ('включена.' if info['is_enabled'] else 'отключена.'))
            return
        if 'deleted_business_messages' in u:
            d = u['deleted_business_messages']
            conn = d['business_connection_id']
            if not self.connection(conn):
                return
            for mid in d['message_ids']:
                row = self.db.execute('SELECT body FROM messages WHERE conn=? AND chat=? AND id=?',
                                      (conn,d['chat']['id'],mid)).fetchone()
                m = json.loads(row[0]) if row else None
                self.enqueue(f'{uid}:{mid}', 'Удалено сообщение\n' + (describe(m) if m else
                             f'Чат: {d["chat"]["id"]} | Сообщение: {mid}\nКопия отсутствует: бот не успел его сохранить.'), m)
            return
        edited = 'edited_business_message' in u
        m = u.get('edited_business_message') or u.get('business_message')
        if not m:
            return
        conn = m['business_connection_id']
        if not self.connection(conn):
            return
        row = self.db.execute('SELECT body FROM messages WHERE conn=? AND chat=? AND id=?',
                              (conn,m['chat']['id'],m['message_id'])).fetchone()
        old = json.loads(row[0]) if row else None
        self.save(conn,m)
        if not edited and old is None:
            self.enqueue(str(uid)+':original', 'Сохранено сообщение\n' + describe(m), m)
        if edited and (not old or signature(old) != signature(m)):
            self.enqueue(str(uid), 'Изменено сообщение\nБыло:\n' +
                         (describe(old) if old else 'Исходная версия отсутствует') + '\n\nСтало:\n' + describe(m), old)
            if attachment(m)[0]:
                self.enqueue(str(uid)+':new', message=m)
        reply = m.get('reply_to_message')
        if not edited and m.get('from',{}).get('id') == owner and reply:
            # Some replies expose media, some only an inaccessible placeholder.
            known = self.db.execute('SELECT body FROM messages WHERE conn=? AND chat=? AND id=?',
                                    (conn,reply['chat']['id'],reply['message_id'])).fetchone()
            if not known:
                self.save(conn,reply)
            kind, _ = attachment(reply)
            self.enqueue(str(uid)+':reply', 'Копия по твоему ответу\n' + describe(reply) +
                         ('' if kind else '\nTelegram не передал доступное вложение.'), reply)

    def download_one(self):
        # Local backups expire after 7 days; metadata and Telegram file_id remain.
        for path in self.media.glob('*.bin'):
            if path.stat().st_mtime < time.time()-7*86400:
                path.unlink()
                with self.db:
                    self.db.execute("UPDATE files SET path=NULL,state='expired' WHERE path=?", (str(path),))
        row = self.db.execute("SELECT id,attempts FROM files WHERE state='pending' AND next_try<=? LIMIT 1",
                              (time.time(),)).fetchone()
        if not row:
            return
        fid, attempts = row
        used = sum(p.stat().st_size for p in self.media.glob('*.bin'))
        limit = min(20*1024**2, self.quota-used, shutil.disk_usage(self.root).free-2*1024**3)
        if limit <= 0:
            state, path = 'pending', None
        else:
            dest = self.media / (hashlib.sha256(fid.encode()).hexdigest()+'.bin')
            try:
                self.api.download(fid, dest, limit)
                state, path = 'saved', str(dest)
            except APIError as e:
                state, path = ('unavailable' if e.code in (400,403,404,413) else 'pending'), None
                LOG.warning('Attachment backup: code=%s', e.code)
        with self.db:
            self.db.execute('UPDATE files SET state=?,path=?,attempts=attempts+1,next_try=? WHERE id=?',
                            (state,path,time.time()+(3600 if limit<=0 else min(3600,2**min(attempts+1,11))),fid))

    def deliver_one(self):
        owner = int(self.get('owner'))
        if not owner:
            return
        row = self.db.execute('SELECT key,body,attempts FROM outbox WHERE done=0 AND next_try<=? '
                              'ORDER BY rowid LIMIT 1', (time.time(),)).fetchone()
        if not row:
            return
        key, raw, attempts = row
        body = json.loads(raw)
        try:
            if 'text' in body:
                self.api.call('sendMessage', chat_id=owner, text=body['text'])
            else:
                kind, item = attachment(body['message'])
                fid = item['file_id']
                try:
                    self.api.call(MEDIA[kind], chat_id=owner, **{kind:fid})
                except APIError as e:
                    if e.code != 400:
                        raise
                    backup = self.db.execute("SELECT path FROM files WHERE id=? AND state='saved'", (fid,)).fetchone()
                    if backup and Path(backup[0]).is_file():
                        self.api.call(MEDIA[kind], upload=(kind, backup[0]), chat_id=owner)
                    else:
                        self.api.call('sendMessage', chat_id=owner,
                                      text='Вложение недоступно для копирования. Локальная копия отсутствует.')
            with self.db:
                self.db.execute('UPDATE outbox SET done=1 WHERE key=?', (key,))
        except APIError as e:
            delay = max(e.delay, min(3600, 2**min(attempts+1,11)))
            with self.db:
                self.db.execute('UPDATE outbox SET attempts=attempts+1,next_try=? WHERE key=?',
                                (time.time()+delay,key))
            LOG.warning('Notification retry: code=%s', e.code)


def main():
    os.umask(0o077)
    logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')
    config = json.loads(Path(os.environ.get('CUSTOS_CONFIG','/etc/custos/config.json')).read_text())
    bot = Custos(config.get('data_dir','/var/lib/custos'), API(config['token']), config['setup_code'])
    import fcntl
    lock = (bot.root / 'process.lock').open('w')
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    running = True
    def stop(*_):
        nonlocal running
        running = False
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    bot.api.call('getMe')
    webhook = bot.api.call('getWebhookInfo')
    if webhook.get('url'):
        raise SystemExit('Webhook already configured. Stop existing deployment before polling.')
    LOG.info('Custos 0.2 started')
    while running:
        try:
            updates = bot.api.call('getUpdates', offset=int(bot.get('offset')), timeout=5,
                                   allowed_updates=UPDATES)
            bot.ingest(updates)
            bot.process()
            for _ in range(10):
                bot.deliver_one()
        except APIError as error:
            LOG.warning('Telegram connection: code=%s', error.code)
            time.sleep(max(2, min(error.delay, 30)))
        except Exception as error:
            LOG.error('Internal error type=%s', type(error).__name__)
            time.sleep(3)
    bot.db.close()


if __name__ == '__main__':
    main()
