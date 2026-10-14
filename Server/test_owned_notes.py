"""New-device journal synchronization must not depend on a truncated friend feed."""
import json
import unittest
import uuid
from server import PlazaService
from test_server import avatar

class OwnedNoteTests(unittest.TestCase):
    def test_complete_owner_payloads_exclude_friends_and_interactions(self):
        service = PlazaService(':memory:', 'http://127.0.0.1:8787')
        try:
            token = service.create_session('10', 'Windows')['token']
            other = service.create_session('20', 'Mac')['token']
            author = avatar()
            author['id'] = str(uuid.uuid4())
            notes = [dict(id=str(uuid.uuid4()), author=author, text='Note '+str(i), drawing=[],
                          drawingDescription='', created=service.now()-i) for i in range(200)]
            service.handle('PUT', '/v1/notes', dict(notes=notes), token)
            aid = service.account(token)['id']
            # Simulate many old discussions: the ordinary feed has a 2,000
            # reply budget and may omit notes. Publisher recovery must not.
            for row in service.db.execute('SELECT id FROM journal_notes WHERE owner=?',(aid,)).fetchall():
                for _ in range(11):
                    rid = str(uuid.uuid4())
                    service.db.execute('INSERT INTO journal_replies VALUES (?,?,?,?,?,?)',
                        (aid,row['id'],rid,aid,json.dumps(dict(id=rid,ownerID=aid,author=author,text='Earlier reply',created=0)),0))
            self.assertLess(len(service.handle('GET','/v1/notes/threads',{},token)['notes']),200)
            owned = service.handle('GET','/v1/notes/owned',{},token)['notes']
            self.assertEqual(len(owned),200)
            self.assertEqual({n['sourceID'] for n in owned},{n['id'] for n in notes})
            self.assertTrue(all('replies' not in n for n in owned))
            self.assertEqual(service.handle('GET','/v1/notes/owned',{},other)['notes'],[])
        finally:
            service.db.close()
