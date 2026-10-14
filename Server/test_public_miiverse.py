"""Public Miiverse remains authenticated and enforces each post's audience."""
import json
import threading
import unittest
import urllib.request
import urllib.error
import uuid
import test_server as fixtures
from server import APIError, make_server

class PublicMiiverseTests(unittest.TestCase):
    setUp = fixtures.ServiceTests.setUp
    tearDown = fixtures.ServiceTests.tearDown
    login = fixtures.ServiceTests.login
    call = fixtures.ServiceTests.call
    snapshot = fixtures.ServiceTests.snapshot
    journal_note = fixtures.ServiceTests.journal_note
    request = fixtures.ServiceTests.request
    befriend = fixtures.ServiceTests.befriend

    def post(self, **changes):
        note = self.journal_note(audience='public', **changes)
        self.call(self.a, 'PUT', 'notes', notes=[note])
        return note, self.call(self.b, 'GET', 'notes')['notes'][0]['id']

    def test_strangers_read_public_posts_but_not_friends_only_by_same_author(self):
        public = self.journal_note(audience='public', text='Everyone')
        friends = self.journal_note(audience='friends', text='Friends')
        self.call(self.a, 'PUT', 'notes', notes=[public, friends])
        for token in (self.b, self.c):
            feed = self.call(token, 'GET', 'notes')['notes']
            self.assertEqual([n['text'] for n in feed], ['Everyone'])
            self.assertFalse(feed[0]['isFriend'])
            self.assertEqual(feed[0]['audience'], 'public')
            self.assertEqual(feed[0]['displayName'], 'Alice')
        self.befriend()
        feed = self.call(self.b, 'GET', 'notes')['notes']
        self.assertEqual({n['text'] for n in feed}, {'Everyone', 'Friends'})
        self.assertTrue(all(n['isFriend'] for n in feed))
        self.assertEqual(self.snapshot(self.c)['friends'], [], 'Reading a public post never creates a friendship')

    def test_legacy_posts_stay_friends_only_and_invalid_audiences_preserve_content(self):
        note = self.journal_note()
        self.call(self.a, 'PUT', 'notes', notes=[note])
        self.assertEqual(self.call(self.b, 'GET', 'notes')['notes'], [])
        self.befriend()
        self.assertEqual(self.call(self.b, 'GET', 'notes')['notes'][0]['audience'], 'friends')
        before = self.call(self.a, 'GET', 'notes/owned')
        for bad in ('private', 'everyone', '', None, [], {}):
            with self.assertRaises(APIError):
                self.call(self.a, 'PUT', 'notes', notes=[dict(note, audience=bad)])
            self.assertEqual(self.call(self.a, 'GET', 'notes/owned'), before)

    def test_unrelated_discord_accounts_like_reply_and_receive_verified_names(self):
        note, nid = self.post(displayName='Forged Alice', discordID='999')
        self.call(self.b, 'PUT', 'notes/'+nid+'/like', liked=True)
        rid = str(uuid.uuid4())
        self.call(self.b, 'PUT', 'notes/'+nid+'/replies/'+rid, author=note['author'], text='Hello everyone', displayName='Forged Bob', ownerID=self.service.account(self.a)['id'])
        thread = self.call(self.c, 'GET', 'notes')['notes'][0]
        self.assertEqual(thread['likeCount'], 1)
        self.assertEqual(thread['displayName'], 'Alice')
        self.assertEqual(thread['discordID'], '100')
        self.assertEqual(thread['replies'][0]['displayName'], 'Bob')
        self.assertEqual(thread['replies'][0]['ownerID'], self.service.account(self.b)['id'])
        self.assertEqual(self.call(self.a, 'GET', 'notes/activity')['unreadCount'], 2)
        with self.assertRaises(APIError):
            self.call(self.c, 'PUT', 'notes/'+nid+'/replies/'+rid, author=note['author'], text='Overwrite')
        self.call(self.a, 'DELETE', 'notes/'+nid+'/replies/'+rid)
        self.assertEqual(self.call(self.c, 'GET', 'notes')['notes'][0]['replies'], [])

    def test_narrowing_public_to_friends_or_private_revokes_nonfriend_reads_and_actions(self):
        note, nid = self.post()
        self.call(self.b, 'PUT', 'notes/'+nid+'/like', liked=True)
        note['audience'] = 'friends'
        self.call(self.a, 'PUT', 'notes', notes=[note])
        for token in (self.b, self.c):
            self.assertEqual(self.call(token, 'GET', 'notes')['notes'], [])
            with self.assertRaises(APIError): self.call(token, 'PUT', 'notes/'+nid+'/like', liked=True)
            with self.assertRaises(APIError): self.call(token, 'PUT', 'notes/'+nid+'/replies/'+str(uuid.uuid4()), author=note['author'], text='No access')
        self.assertEqual(self.call(self.a, 'GET', 'notes/activity')['activities'], [])
        self.befriend()
        self.assertEqual(self.call(self.b, 'GET', 'notes')['notes'][0]['id'], nid)
        self.call(self.a, 'PUT', 'notes', notes=[])
        self.assertEqual(self.call(self.b, 'GET', 'notes')['notes'], [])
        self.assertEqual(self.service.db.execute('SELECT count(*) FROM journal_likes').fetchone()[0], 0)

    def test_nonfriends_can_block_public_authors_and_blocks_override_public(self):
        note, nid = self.post()
        self.call(self.b, 'PUT', 'notes/'+nid+'/like', liked=True)
        aid = self.service.account(self.a)['id']
        self.call(self.b, 'POST', 'friends/block', id=aid)
        self.assertEqual(self.call(self.b, 'GET', 'notes')['notes'], [])
        with self.assertRaises(APIError): self.call(self.b, 'PUT', 'notes/'+nid+'/like', liked=True)
        self.assertEqual(self.call(self.a, 'GET', 'notes/threads')['notes'][0]['likeCount'], 0)
        self.call(self.b, 'POST', 'friends/unblock', id=aid)
        self.assertEqual(len(self.call(self.b, 'GET', 'notes')['notes']), 1)

    def test_public_feed_remains_bounded(self):
        for token in (self.a, self.b):
            self.call(token, 'PUT', 'notes', notes=[self.journal_note(audience='public', text=str(i)) for i in range(200)])
        notes = self.call(self.c, 'GET', 'notes/threads')['notes']
        self.assertEqual(len(notes), 300)
        self.assertTrue(all(n['audience']=='public' for n in notes))

    def test_real_http_requires_valid_discord_backed_sessions_for_public_reads_and_writes(self):
        note, nid = self.post()
        server = make_server(self.service, port=0)
        worker = threading.Thread(target=server.serve_forever, daemon=True); worker.start()
        base='http://127.0.0.1:'+str(server.server_port)+'/v1/'
        def request(path, token=None, body=None):
            headers={'Content-Type':'application/json'}
            if token: headers['Authorization']='Bearer '+token
            req=urllib.request.Request(base+path, headers=headers, data=json.dumps(body).encode() if body is not None else None, method='PUT' if body is not None else 'GET')
            with urllib.request.urlopen(req) as response: return json.load(response)
        try:
            for token in (None, 'unverified-discord-id'):
                for path, body in [('notes/threads', None), ('notes/'+nid+'/like', {'liked':True})]:
                    with self.assertRaises(urllib.error.HTTPError) as error: request(path, token, body)
                    self.assertEqual(error.exception.code, 401)
            self.assertEqual(request('notes/threads', self.b)['notes'][0]['displayName'], 'Alice')
            self.assertTrue(request('notes/'+nid+'/like', self.b, {'liked':True})['liked'])
            self.call(self.b, 'POST', 'logout')
            with self.assertRaises(urllib.error.HTTPError) as error: request('notes/threads', self.b)
            self.assertEqual(error.exception.code, 401)
        finally:
            server.shutdown(); server.server_close(); worker.join()
