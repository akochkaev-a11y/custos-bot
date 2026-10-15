import json
from pathlib import Path
import tempfile
import time
import unittest
from custos import APIError, Custos


class FakeAPI:
    def __init__(self):
        self.calls = []
        self.fail = None

    def call(self, method, **params):
        self.calls.append((method,params))
        if self.fail:
            raise self.fail
        if method == 'getBusinessConnection':
            return {'user': {'id':42}, 'is_enabled':True}
        return True

    def download(self, fid, dest, limit):
        dest.write_bytes(b'backup')


def message(mid=1, text='Первый текст', author=100, chat=123):
    return {'message_id':mid,'date':1792030000,'chat':{'id':chat,'type':'private'},
            'from':{'id':author,'first_name':'Test'},'text':text,'business_connection_id':'conn'}


class ArchiveTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.api = FakeAPI()
        self.bot = Custos(self.temp.name,self.api,'pair-code')

    def tearDown(self):
        self.bot.db.close()
        self.temp.cleanup()

    def event(self, uid, **event):
        self.bot.ingest([{'update_id':uid,**event}])
        self.bot.process()

    def pair(self):
        self.event(10,message=message(text='/start pair-code',author=42))

    def queued(self):
        return [json.loads(r[0]) for r in self.bot.db.execute('SELECT body FROM outbox')]

    def test_pair_requires_code(self):
        self.event(1,message=message(text='/start',author=99))
        self.assertEqual(self.bot.get('owner'),'0')
        self.pair()
        self.assertEqual(self.bot.get('owner'),'42')
        self.event(11,message=message(text='/start pair-code',author=99))
        self.assertEqual(self.bot.get('owner'),'42')

    def test_deferred_business_before_pairing(self):
        self.event(1,business_message=message())
        self.assertEqual(self.bot.db.execute('SELECT count(*) FROM messages').fetchone()[0],0)
        self.pair()
        self.assertEqual(self.bot.db.execute('SELECT count(*) FROM messages').fetchone()[0],1)

    def test_new_message_is_copied_immediately_without_local_download(self):
        self.pair()
        m = message()
        m['photo'] = [{'file_id':'fid','file_unique_id':'unique'}]
        self.event(11,business_message=m)
        self.assertTrue(any('Сохранено сообщение' in q.get('text','') for q in self.queued()))
        self.assertTrue(any(q.get('message',{}).get('photo') for q in self.queued()))
        self.assertEqual(self.bot.db.execute('SELECT count(*) FROM files').fetchone()[0],0)
        count = len(self.queued())
        self.event(12,business_message=m)
        self.assertEqual(len(self.queued()),count)

    def test_original_and_edit(self):
        self.pair()
        self.event(11,business_message=message())
        changed=message(text='Новый текст')
        self.event(12,edited_business_message=changed)
        texts=' '.join(q.get('text','') for q in self.queued())
        self.assertIn('Первый текст',texts)
        self.assertIn('Новый текст',texts)
        self.assertEqual(self.bot.db.execute('SELECT count(*) FROM versions').fetchone()[0],2)

    def test_metadata_edit_does_not_notify(self):
        self.pair()
        self.event(11,business_message=message())
        count=len(self.queued())
        changed=message()
        changed['edit_date']=99
        self.event(12,edited_business_message=changed)
        self.assertEqual(len(self.queued()),count)

    def test_delete_and_unknown(self):
        self.pair()
        self.event(11,business_message=message())
        self.event(12,deleted_business_messages={'business_connection_id':'conn','chat':{'id':123},'message_ids':[1,2]})
        texts=' '.join(q.get('text','') for q in self.queued())
        self.assertIn('Удалено сообщение',texts)
        self.assertIn('Первый текст',texts)
        self.assertIn('Копия отсутствует',texts)

    def test_chat_ids_are_separate(self):
        self.pair()
        self.event(11,business_message=message(chat=123))
        self.event(12,business_message=message(chat=456))
        self.assertEqual(self.bot.db.execute('SELECT count(*) FROM messages').fetchone()[0],2)

    def test_duplicate_update_not_requeued(self):
        self.pair()
        self.event(11,business_message=message())
        self.event(12,edited_business_message=message(text='changed'))
        count=len(self.queued())
        self.event(12,edited_business_message=message(text='changed'))
        self.assertEqual(len(self.queued()),count)

    def test_foreign_connection_is_ignored(self):
        self.pair()
        self.api.call=lambda method,**kwargs: {'user':{'id':99},'is_enabled':True}
        self.event(11,business_message=message())
        self.assertEqual(self.bot.db.execute('SELECT count(*) FROM messages').fetchone()[0],0)

    def test_reply_media_and_unavailable(self):
        self.pair()
        reply=message()
        reply['photo']=[{'file_id':'fid','file_unique_id':'unique'}]
        m=message(mid=2,text='👍',author=42)
        m['reply_to_message']=reply
        self.event(11,business_message=m)
        self.assertTrue(any(q.get('message',{}).get('photo') for q in self.queued()))
        m=message(mid=3,text='.',author=42)
        m['reply_to_message']=message(mid=4)
        self.event(12,business_message=m)
        self.assertTrue(any('не передал' in q.get('text','') for q in self.queued()))

    def test_restart_keeps_offset_and_queue(self):
        self.pair()
        self.bot.db.close()
        self.bot=Custos(self.temp.name,self.api,'pair-code')
        self.assertEqual(self.bot.get('owner'),'42')
        self.assertEqual(self.bot.get('offset'),'11')
        self.assertTrue(self.queued())

    def test_delivery_retry_retains_payload(self):
        self.pair()
        self.api.fail=APIError(429,60)
        self.bot.deliver_one()
        done,attempts,next_try=self.bot.db.execute('SELECT done,attempts,next_try FROM outbox').fetchone()
        self.assertEqual((done,attempts),(0,1))
        self.assertGreater(next_try,time.time()+50)
        self.api.fail=None
        self.bot.db.execute('UPDATE outbox SET next_try=0')
        self.bot.deliver_one()
        self.assertEqual(self.bot.db.execute('SELECT done FROM outbox').fetchone()[0],1)

    def test_media_local_fallback(self):
        self.pair()
        m=message()
        m['photo']=[{'file_id':'fid','file_unique_id':'unique'}]
        self.event(11,business_message=m)
        self.bot.db.execute("INSERT OR IGNORE INTO files(id,state) VALUES('fid','pending')")
        self.bot.download_one()
        self.assertEqual(self.bot.db.execute('SELECT state FROM files').fetchone()[0],'saved')
        self.bot.db.execute('DELETE FROM outbox')
        self.bot.enqueue('fallback',message=m)
        calls=[]
        def send(method,**params):
            calls.append(params)
            if 'upload' not in params:
                raise APIError(400)
            return True
        self.api.call=send
        self.bot.deliver_one()
        self.assertEqual(len(calls),2)
        self.assertIn('upload',calls[1])


if __name__=='__main__':
    unittest.main()
