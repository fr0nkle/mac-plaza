import copy
import json
import math
import threading
import unittest
import urllib.error
import urllib.request
from server import APIError, PlazaService, challenge, digest, make_server, validated_avatar


def avatar():
    features = dict(eyeColor=0, browColor=1, mouthColor=0, glassesType=1, glassesColor=0,
                    mustache=0, beardType=1, facialHairColor=1, wrinkles=0, makeup=0, gender=0,
                    mole=False, flipHair=False, birthMonth=10, birthDay=12, creator="Private name")
    for key in ("eyeSize eyeStretch eyeRotation eyeY browSize browStretch browRotation browSpacing browY "
                "noseSize noseY mouthSize mouthStretch mouthY glassesSize glassesY mustacheSize mustacheY moleSize moleX moleY").split():
        features[key] = 0.5
    return dict(id="untrusted-client-id", name="Test Mii", skin=0, hair=33, hairColor=1,
                eyes=2, brows=0, nose=1, mouth=23, face=0, outfit=0, glasses=False, beard=False,
                eyeSpacing=0.5, featureHeight=0.5, height=0.5, build=0.5, features=features)


class ServiceTests(unittest.TestCase):
    def test_discord_mii_sharing_uses_publishers_grants_without_invitations(self):
        self.publish(self.a, shareDiscordFriends=True)
        self.assertEqual(self.snapshot(self.b)["friends"], [])
        self.call(self.a, "PUT", "discord/recipients", discordIDs=["200"])
        shared = self.snapshot(self.b)["friends"]
        self.assertEqual([f["discordID"] for f in shared], ["100"])
        self.assertEqual(shared[0]["avatar"]["features"]["creator"], "")
        self.assertEqual(self.snapshot(self.b)["incoming"], [])
        self.assertEqual(self.snapshot(self.c)["friends"], [])
        # A viewer declaring a publisher to be their friend grants access only
        # to the viewer's OWN profile; it cannot authorize reading that publisher.
        self.publish(self.c, shareDiscordFriends=True)
        self.call(self.c, "PUT", "discord/recipients", discordIDs=["100"])
        self.assertEqual(self.snapshot(self.c)["friends"], [])
        self.call(self.a, "PUT", "discord/recipients", discordIDs=[])
        self.assertEqual(self.snapshot(self.b)["friends"], [])

    def test_discord_mii_sharing_revocation_blocks_and_expiry(self):
        self.publish(self.a, shareDiscordFriends=True)
        self.call(self.a, "PUT", "discord/recipients", discordIDs=["200"])
        alice = self.snapshot(self.b)["friends"][0]["id"]
        self.call(self.b, "POST", "friends/block", id=alice)
        self.assertEqual(self.snapshot(self.b)["friends"], [])
        self.call(self.b, "POST", "friends/unblock", id=alice)
        self.assertEqual(len(self.snapshot(self.b)["friends"]), 1)
        self.publish(self.a, shareDiscordFriends=False)
        self.assertEqual(self.snapshot(self.b)["friends"], [])
        self.assertEqual(self.service.db.execute("SELECT count(*) FROM discord_recipients").fetchone()[0], 0)
        self.publish(self.a, shareDiscordFriends=True)
        self.call(self.a, "PUT", "discord/recipients", discordIDs=["200"])
        self.clock += 7 * 86400 + 1
        with self.service.lock:
            me = self.service.db.execute("SELECT * FROM accounts WHERE discord_id='200'").fetchone()
            self.assertEqual(self.service.snapshot(me)["friends"], [])

    def test_discord_recipients_require_consent_validate_and_cascade(self):
        with self.assertRaises(APIError):
            self.call(self.a, "PUT", "discord/recipients", discordIDs=["200"])
        self.publish(self.a, shareDiscordFriends=True)
        for invalid in (["bad"], ["0"], ["200"] * 1001, "200", [2], ["9" * 100]):
            with self.assertRaises(APIError):
                self.call(self.a, "PUT", "discord/recipients", discordIDs=invalid)
        self.call(self.a, "PUT", "discord/recipients", discordIDs=["200", "200", "100"])
        self.assertEqual(self.service.db.execute("SELECT count(*) FROM discord_recipients").fetchone()[0], 1)
        self.call(self.a, "DELETE", "account")
        self.assertEqual(self.service.db.execute("SELECT count(*) FROM discord_recipients").fetchone()[0], 0)

    def test_discord_friends_authorization_is_bound_to_login_and_tokens_stay_out_of_database(self):
        start = self.call(self.a, "POST", "auth/start", challenge=challenge("a" * 43), friendDiscovery=True)
        self.assertIn("sdk.social_layer_presence", start["authorizeURL"])
        credentials = dict(applicationID="client", discordID="100", accessToken="private-access", refreshToken="private-refresh", expiresAt=self.clock + 3600)
        self.service.discord_identity = lambda code, include_friends=False: dict(id="100", name="Alice", discordSDK=credentials.copy())
        self.service.callback(start["state"], "code")
        stored = self.service.db.execute("SELECT identity FROM logins WHERE state=?", (start["state"],)).fetchone()[0]
        self.assertNotIn("private-access", stored)
        self.assertNotIn("private-refresh", stored)
        with self.assertRaises(APIError):
            self.service.finish_login(start["state"], "b" * 43)
        result = self.service.finish_login(start["state"], "a" * 43)
        self.assertEqual(result["discordSDK"], credentials)
        self.assertEqual(self.service.sdk_logins, {})
        self.assertEqual(self.snapshot(result["token"])["account"]["id"], self.snapshot(self.a)["account"]["id"])

    def test_discord_sdk_refresh_requires_the_same_linked_identity_and_presence_scope(self):
        tokens = dict(access_token="access", refresh_token="refresh", expires_in=3600, scope="identify openid sdk.social_layer_presence")
        self.service.discord_request = lambda url, data=None, token=None: tokens if url == "oauth2/token" else {"id": "100"}
        result = self.call(self.a, "POST", "discord/refresh", refreshToken="old-refresh")
        self.assertEqual(result["discordID"], "100")
        self.assertEqual(result["expiresAt"], self.clock + 3600)
        with self.assertRaises(APIError):
            self.call(self.b, "POST", "discord/refresh", refreshToken="old-refresh")
        tokens["scope"] = "identify"
        with self.assertRaises(APIError):
            self.call(self.a, "POST", "discord/refresh", refreshToken="old-refresh")

    def setUp(self):
        self.clock = 100000
        self.service = PlazaService(":memory:", "http://127.0.0.1:8787", "client", "secret", now=lambda: self.clock)
        self.a = self.login("100", "Alice")
        self.b = self.login("200", "Bob")
        self.c = self.login("300", "Charlie")

    def tearDown(self):
        self.service.db.close()

    def login(self, user, name):
        with self.service.lock, self.service.db:
            return self.service.create_session(user, name)["token"]

    def call(self, token, method, path, **data):
        return self.service.handle(method, "/v1/" + path, data, token)

    def snapshot(self, token):
        return self.call(token, "GET", "snapshot")

    def publish(self, token, **overrides):
        values = dict(avatar=avatar(), note="Hello plaza!", sharing=True, sharePresence=True)
        values.update(overrides)
        return self.call(token, "PUT", "profile", **values)

    def request(self, sender, recipient):
        code = self.call(recipient, "POST", "invites")["code"]
        return self.call(sender, "POST", "friends/request", code=code)

    def befriend(self):
        self.request(self.a, self.b)
        aid = self.snapshot(self.a)["account"]["id"]
        self.call(self.b, "POST", "friends/accept", id=aid)

    def journal_note(self, **overrides):
        import uuid
        result = dict(id=str(uuid.uuid4()), author=avatar(), text="Hello Bloons!", drawing=[],
                      drawingDescription="", created=self.clock,
                      topic=dict(label="Bloons TD6", bundleID="com.plaza.steam.960090", steamAppID=960090))
        result["author"]["id"] = str(uuid.uuid4())
        result.update(overrides)
        return result

    def test_shared_notes_matchable_topics_plaza_and_owner_identity(self):
        self.befriend()
        note = self.journal_note()
        plaza = self.journal_note(text="Hello plaza", topic=None)
        self.call(self.a, "PUT", "notes", notes=[note, plaza])
        received = self.call(self.b, "GET", "notes")["notes"]
        self.assertEqual({n["text"] for n in received}, {"Hello Bloons!", "Hello plaza"})
        game = next(n for n in received if n["topic"])
        self.assertEqual(game["topic"]["steamAppID"], 960090)
        self.assertEqual(game["ownerID"], self.snapshot(self.a)["account"]["id"])
        self.assertNotEqual(game["id"], note["id"])
        self.assertNotEqual(game["author"]["id"], note["author"]["id"])
        self.assertEqual(game["author"]["features"]["creator"], "")
        self.assertEqual(self.call(self.c, "GET", "notes")["notes"], [])

    def test_shared_notes_edit_delete_and_private_replacement(self):
        self.befriend()
        note = self.journal_note()
        self.call(self.a, "PUT", "notes", notes=[note])
        first = self.call(self.b, "GET", "notes")["notes"][0]
        note["text"] = "Edited"
        self.call(self.a, "PUT", "notes", notes=[note])
        edited = self.call(self.b, "GET", "notes")["notes"][0]
        self.assertEqual(edited["id"], first["id"])
        self.assertEqual(edited["author"]["id"], first["author"]["id"])
        self.assertEqual(edited["text"], "Edited")
        self.call(self.a, "PUT", "notes", notes=[])
        self.assertEqual(self.call(self.b, "GET", "notes")["notes"], [])

    def test_shared_notes_discord_grants_blocking_and_revocation(self):
        self.publish(self.a, shareDiscordFriends=True)
        self.call(self.a, "PUT", "discord/recipients", discordIDs=["200"])
        self.call(self.a, "PUT", "notes", notes=[self.journal_note()])
        self.assertEqual(len(self.call(self.b, "GET", "notes")["notes"]), 1)
        aid = self.snapshot(self.a)["account"]["id"]
        self.call(self.b, "POST", "friends/block", id=aid)
        self.assertEqual(self.call(self.b, "GET", "notes")["notes"], [])
        self.call(self.b, "POST", "friends/unblock", id=aid)
        self.assertEqual(len(self.call(self.b, "GET", "notes")["notes"]), 1)
        self.call(self.a, "PUT", "discord/recipients", discordIDs=[])
        self.assertEqual(self.call(self.b, "GET", "notes")["notes"], [])
        self.call(self.c, "PUT", "notes", notes=[self.journal_note(ownerID=aid)])
        self.assertEqual(self.call(self.b, "GET", "notes")["notes"], [])

    def test_shared_notes_invalid_batch_preserves_existing_and_is_bounded(self):
        self.befriend()
        note = self.journal_note()
        self.call(self.a, "PUT", "notes", notes=[note])
        expected = self.call(self.b, "GET", "notes")
        for bad in ([note, note], [self.journal_note(text="x" * 281)],
                    [self.journal_note(topic=dict(label="Bad", bundleID="bad", steamAppID=0))],
                    [self.journal_note(drawing=[dict(points=[dict(x=2, y=0)], eraser=False)], drawingDescription="Bad")],
                    [self.journal_note() for _ in range(201)]):
            with self.assertRaises(APIError):
                self.call(self.a, "PUT", "notes", notes=bad)
            self.assertEqual(self.call(self.b, "GET", "notes"), expected)

    def test_shared_drawings_strip_unrelated_fields_and_account_delete_cascades(self):
        self.befriend()
        note = self.journal_note(text="", drawing=[dict(points=[dict(x=0.5,y=0.5)], eraser=False)],
                                 drawingDescription="A dot", replies=[dict(text="Private reply")],
                                 bookmark="private", path="/Users/private")
        self.call(self.a, "PUT", "notes", notes=[note])
        received = self.call(self.b, "GET", "notes")["notes"][0]
        self.assertEqual(received["drawing"], note["drawing"])
        self.assertEqual(received["replies"], [])  # Private local replies were not uploaded.
        for key in ("bookmark", "path"):
            self.assertNotIn(key, received)
        self.call(self.a, "DELETE", "account")
        self.assertEqual(self.service.db.execute("SELECT count(*) FROM journal_notes").fetchone()[0], 0)

    def test_oauth_bound_to_verifier_and_single_use(self):
        verifier = "a" * 43
        start = self.service.start_login(challenge(verifier))
        self.service.discord_identity = lambda code: {"id": "400", "name": "Dani"}
        self.assertTrue(self.service.callback(start["state"], "code").startswith("macplaza://discord-linked?"))
        with self.assertRaises(APIError):
            self.service.finish_login(start["state"], "b" * 43)
        token = self.service.finish_login(start["state"], verifier)["token"]
        self.assertEqual(self.snapshot(token)["account"]["displayName"], "Dani")
        with self.assertRaises(APIError):
            self.service.finish_login(start["state"], verifier)
        self.assertIsNone(self.service.db.execute("SELECT * FROM sessions WHERE hash=?", (token,)).fetchone())
        self.assertIsNotNone(self.service.db.execute("SELECT * FROM sessions WHERE hash=?", (digest(token),)).fetchone())

    def test_expired_and_replayed_callbacks_are_rejected(self):
        start = self.service.start_login(challenge("a" * 43))
        self.clock += 301
        with self.assertRaises(APIError):
            self.service.callback(start["state"], "code")
        start = self.service.start_login(challenge("a" * 43))
        self.service.discord_identity = lambda code: {"id": "400", "name": "Dani"}
        self.service.callback(start["state"], "code")
        with self.assertRaises(APIError):
            self.service.callback(start["state"], "code")

    def test_sharing_requires_acceptance_and_does_not_leak_to_third_account(self):
        self.publish(self.a)
        self.publish(self.b)
        self.request(self.a, self.b)
        self.assertEqual(self.snapshot(self.a)["friends"], [])
        self.assertEqual(self.snapshot(self.b)["friends"], [])
        aid = self.snapshot(self.a)["account"]["id"]
        with self.assertRaises(APIError):
            self.call(self.c, "POST", "friends/accept", id=aid)
        self.call(self.b, "POST", "friends/accept", id=aid)
        self.assertEqual(self.snapshot(self.a)["friends"][0]["displayName"], "Bob")
        self.assertEqual(self.snapshot(self.c)["friends"], [])

    def test_invites_are_single_use_rotatable_and_expire(self):
        code = self.call(self.b, "POST", "invites")["code"]
        self.call(self.a, "POST", "friends/request", code=code)
        with self.assertRaises(APIError):
            self.call(self.c, "POST", "friends/request", code=code)
        code = self.call(self.b, "POST", "invites")["code"]
        self.clock += 86401
        with self.assertRaises(APIError):
            self.call(self.c, "POST", "friends/request", code=code)

    def test_unpublishing_removes_mii_but_keeps_contact_manageable(self):
        self.publish(self.b)
        self.befriend()
        self.assertEqual(len(self.snapshot(self.a)["friends"]), 1)
        self.publish(self.b, sharing=False)
        snapshot = self.snapshot(self.a)
        self.assertEqual(snapshot["friends"], [])
        self.assertEqual(len(snapshot["contacts"]), 1)
        self.assertEqual(snapshot["unlinkedFriends"][0]["displayName"], "Bob")
        self.assertNotIn("avatar", snapshot["unlinkedFriends"][0])
        self.assertNotIn("note", snapshot["unlinkedFriends"][0])

    def test_unlinked_friends_receive_only_consented_status_and_activity(self):
        self.request(self.a, self.b)
        self.assertEqual(self.snapshot(self.a)["unlinkedFriends"], [])
        aid = self.snapshot(self.a)["account"]["id"]
        self.call(self.b, "POST", "friends/accept", id=aid)
        friend = self.snapshot(self.a)["unlinkedFriends"][0]
        self.assertEqual(friend["presence"], "unknown")
        self.assertFalse(friend["plazaOnline"])
        self.assertEqual(friend["activities"], [])
        self.call(self.b, "PUT", "profile", avatar=None, note="Private note", sharing=False, sharePresence=True, shareActivity=True)
        self.service.bot_connected = True
        self.service.set_presence("guild", "200", "online", "Great Game")
        self.call(self.b, "POST", "heartbeat", active=True, application=dict(name="Music", bundleID="com.apple.Music"))
        friend = self.snapshot(self.a)["unlinkedFriends"][0]
        self.assertEqual(friend["presence"], "online")
        self.assertTrue(friend["plazaOnline"])
        self.assertEqual({a["name"] for a in friend["activities"]}, {"Music", "Great Game"})
        self.assertNotIn("note", friend)
        self.assertEqual(self.snapshot(self.c)["unlinkedFriends"], [])
        self.publish(self.b)
        self.assertEqual(self.snapshot(self.a)["unlinkedFriends"], [])
        self.assertEqual(len(self.snapshot(self.a)["friends"]), 1)
        self.publish(self.b, sharing=False, sharePresence=False, shareActivity=False)
        friend = self.snapshot(self.a)["unlinkedFriends"][0]
        self.assertEqual(friend["presence"], "unknown")
        self.assertFalse(friend["plazaOnline"])
        self.assertEqual(friend["activities"], [])
        bid = self.snapshot(self.b)["account"]["id"]
        self.call(self.a, "POST", "friends/block", id=bid)
        self.assertEqual(self.snapshot(self.a)["unlinkedFriends"], [])
        self.assertEqual(self.snapshot(self.b)["unlinkedFriends"], [])

    def test_block_removes_both_directions_and_prevents_new_requests(self):
        self.publish(self.a)
        self.publish(self.b)
        self.befriend()
        bid = self.snapshot(self.b)["account"]["id"]
        self.call(self.a, "POST", "friends/block", id=bid)
        self.assertEqual(self.snapshot(self.a)["friends"], [])
        self.assertEqual(self.snapshot(self.b)["friends"], [])
        code = self.call(self.a, "POST", "invites")["code"]
        with self.assertRaises(APIError):
            self.call(self.b, "POST", "friends/request", code=code)
        self.call(self.a, "POST", "friends/unblock", id=bid)
        self.call(self.b, "POST", "friends/request", code=code)

    def test_presence_consent_disconnect_and_plaza_heartbeat_expiry(self):
        self.publish(self.b, sharePresence=False)
        self.befriend()
        self.service.bot_connected = True
        self.service.set_presence("guild", "200", "online")
        self.assertEqual(self.service.presences, {})

        self.assertEqual(self.snapshot(self.a)["friends"][0]["presence"], "unknown")
        self.publish(self.b, sharePresence=True)
        self.service.set_presence("guild", "200", "idle")
        self.call(self.b, "POST", "heartbeat", active=True)
        friend = self.snapshot(self.a)["friends"][0]
        self.assertEqual(friend["presence"], "idle")
        self.assertTrue(friend["plazaOnline"])
        self.clock += 76
        self.assertFalse(self.snapshot(self.a)["friends"][0]["plazaOnline"])
        self.service.bot_connected = False
        self.assertEqual(self.snapshot(self.a)["friends"][0]["presence"], "unknown")
        self.publish(self.b, sharePresence=False)
        self.assertEqual(self.service.presences, {})

    def test_application_sharing_is_opt_in_expires_and_respects_friend_acl(self):
        self.publish(self.b)
        self.befriend()
        application = dict(name="Music", bundleID="com.apple.Music")
        self.call(self.b, "POST", "heartbeat", active=True, application=application)
        self.assertEqual(self.snapshot(self.a)["friends"][0]["activities"], [])
        self.publish(self.b, shareActivity=True)
        self.call(self.b, "POST", "heartbeat", active=False, application=application)
        activities = self.snapshot(self.a)["friends"][0]["activities"]
        self.assertEqual(activities[0]["name"], "Music")
        self.assertTrue(activities[0]["active"])
        self.assertEqual(self.snapshot(self.c)["friends"], [])
        self.call(self.b, "POST", "heartbeat", active=True)
        self.assertFalse(self.snapshot(self.a)["friends"][0]["activities"][0]["active"])
        self.clock += 1801
        self.assertEqual(self.snapshot(self.a)["friends"][0]["activities"], [])
        self.publish(self.b, shareActivity=False)
        self.assertIsNone(self.service.account(self.b)["activity_name"])

    def test_discord_friend_games_need_no_plaza_invite_and_bind_to_verified_viewer(self):
        calls = []
        def reader(viewer, targets):
            calls.append((viewer, targets))
            return dict(state="ready", coveredDiscordIDs=["200", "999"],
                        games=[dict(discordID="200", name="Great Game"), dict(discordID="999", name="Private Game")])
        self.service.discord_games = reader
        result = self.call(self.a, "POST", "discord/games", discordIDs=["200"], viewer="300")
        self.assertEqual(calls, [("100", ["200"])])
        self.assertEqual(result["coveredDiscordIDs"], ["200"])
        self.assertEqual([g["name"] for g in result["games"]], ["Great Game"])
        self.assertEqual(result["games"][0]["observedAt"], self.clock)
        self.assertEqual(self.service.db.execute("SELECT count(*) FROM friendships").fetchone()[0], 0)
        self.assertEqual(self.service.activities, {})
        self.assertIsNone(self.service.account(self.b)["activity_name"])
        with self.assertRaises(APIError):
            self.call("invalid", "POST", "discord/games", discordIDs=["200"])
        self.befriend()
        self.call(self.a, "POST", "friends/block", id=self.snapshot(self.b)["account"]["id"])
        self.call(self.a, "POST", "discord/games", discordIDs=["200"])
        self.assertEqual(calls[-1], ("100", []))

    def test_discord_friend_game_lookup_is_bounded_and_fails_closed(self):
        for targets in (["invalid"], ["0"], [str(2**64)], ["２００"], [200], ["200"] * 1001, "200"):
            with self.assertRaises(APIError):
                self.call(self.a, "POST", "discord/games", discordIDs=targets)
        self.assertEqual(self.call(self.a, "POST", "discord/games", discordIDs=["200"])["state"], "not-configured")
        self.service.discord_games = lambda viewer, targets: dict(state="unavailable", coveredDiscordIDs=["200"], games=[dict(discordID="200", name="Stale")])
        result = self.call(self.a, "POST", "discord/games", discordIDs=["200"])
        self.assertEqual(result, dict(state="unavailable", coveredDiscordIDs=[], games=[], customStatuses=[]))

    def test_custom_status_lookup_is_scoped_current_and_never_saved(self):
        self.service.discord_games = lambda viewer, targets: dict(state="ready", coveredDiscordIDs=targets,
            games=[], customStatuses=[dict(discordID="200", text="☀️ Making something nice"), dict(discordID="300", text="Private")])
        result = self.call(self.a, "POST", "discord/games", discordIDs=["200"])
        self.assertEqual(result["customStatuses"], [dict(discordID="200", text="☀️ Making something nice", observedAt=self.clock)])
        self.assertEqual(self.service.db.execute("SELECT count(*) FROM friendships").fetchone()[0], 0)
        self.assertNotIn("Making something nice", " ".join(self.service.db.iterdump()))
        self.befriend()
        bid = self.snapshot(self.b)["account"]["id"]
        self.call(self.a, "POST", "friends/block", id=bid)
        self.assertEqual(self.call(self.a, "POST", "discord/games", discordIDs=["200"])["customStatuses"], [])
        self.service.discord_games = lambda viewer, targets: dict(state="unavailable", customStatuses=[dict(discordID="200", text="Stale")])
        self.assertEqual(self.call(self.a, "POST", "discord/games", discordIDs=["200"])["customStatuses"], [])

    def test_discord_game_sharing_and_disconnect_clearance(self):
        self.publish(self.b, shareActivity=True, sharePresence=False)
        self.befriend()
        self.service.bot_connected = True
        self.service.set_presence("guild", "200", "online", "Great Game")
        friend = self.snapshot(self.a)["friends"][0]
        self.assertEqual(friend["presence"], "unknown")
        self.assertEqual(friend["activities"][0]["name"], "Great Game")
        self.service.set_presence("guild", "200", "online")
        self.assertFalse(self.snapshot(self.a)["friends"][0]["activities"][0]["active"])
        self.service.clear_presence(guild="guild")
        self.assertEqual(self.snapshot(self.a)["friends"][0]["activities"], [])

    def test_deletion_revokes_all_sessions_and_removes_shared_data(self):
        self.publish(self.b)
        second = self.login("200", "Bob")
        self.befriend()
        self.call(self.b, "DELETE", "account")
        for token in (self.b, second):
            with self.assertRaises(APIError):
                self.snapshot(token)
        self.assertEqual(self.snapshot(self.a)["friends"], [])
        self.assertEqual(self.service.db.execute("SELECT count(*) FROM friendships").fetchone()[0], 0)

    def test_profile_validation_and_metadata_stripping(self):
        result = self.publish(self.a)["account"]["avatar"]
        self.assertNotEqual(result["id"], "untrusted-client-id")
        self.assertEqual(result["features"]["creator"], "")
        self.assertEqual(result["features"]["birthMonth"], 0)
        for value in (math.inf, math.nan, -1, 999, True, "1"):
            bad = avatar(); bad["height"] = value
            with self.assertRaises(APIError):
                self.publish(self.a, avatar=bad)
        with self.assertRaises(APIError):
            self.publish(self.a, note="x" * 281)
        with self.assertRaises(APIError):
            self.publish(self.a, sharePresence="yes")

    def published_thread(self):
        self.befriend()
        note = self.journal_note()
        self.call(self.a,"PUT","notes",notes=[note])
        return note, self.call(self.b,"GET","notes")["notes"][0]["id"]

    def thread_reply(self, token, note_id, reply_id, body="A shared reply", **extra):
        import uuid
        appearance=avatar();appearance["id"]=str(uuid.uuid4())
        return self.call(token,"PUT","notes/"+note_id+"/replies/"+reply_id,author=appearance,text=body,**extra)

    def test_shared_likes_are_per_account_idempotent_and_visible_to_author(self):
        _,nid=self.published_thread()
        for _ in range(2):self.call(self.b,"PUT","notes/"+nid+"/like",liked=True)
        self.assertEqual(self.call(self.a,"GET","notes/threads")["notes"][0]["likeCount"],1)
        self.assertFalse(self.call(self.a,"GET","notes/threads")["notes"][0]["liked"])
        self.assertTrue(self.call(self.b,"GET","notes")["notes"][0]["liked"])
        self.call(self.a,"PUT","notes/"+nid+"/like",liked=True)
        self.assertEqual(self.call(self.b,"GET","notes")["notes"][0]["likeCount"],2)
        self.call(self.b,"PUT","notes/"+nid+"/like",liked=False)
        self.assertEqual(self.call(self.a,"GET","notes/threads")["notes"][0]["likeCount"],1)
        with self.assertRaises(APIError):self.call(self.c,"PUT","notes/"+nid+"/like",liked=True)

    def test_shared_replies_retry_edit_permissions_and_author_moderation(self):
        import uuid
        _,nid=self.published_thread();rid=str(uuid.uuid4())
        first=self.thread_reply(self.b,nid,rid)["replies"][0]
        self.thread_reply(self.b,nid,rid,"Edited reply",ownerID=self.snapshot(self.a)["account"]["id"])
        replies=self.call(self.a,"GET","notes/threads")["notes"][0]["replies"]
        self.assertEqual(len(replies),1)
        self.assertEqual(replies[0]["ownerID"],self.snapshot(self.b)["account"]["id"])
        self.assertEqual(replies[0]["created"],first["created"])
        self.assertEqual(replies[0]["text"],"Edited reply")
        self.assertEqual(replies[0]["author"]["features"]["creator"],"")
        with self.assertRaises(APIError):self.thread_reply(self.a,nid,rid,"Cannot edit someone else")
        with self.assertRaises(APIError):self.thread_reply(self.c,nid,str(uuid.uuid4()))
        self.call(self.a,"DELETE","notes/"+nid+"/replies/"+rid)
        self.assertEqual(self.call(self.b,"GET","notes")["notes"][0]["replies"],[])

    def test_republishing_and_editing_notes_preserves_interactions_and_retraction_cascades(self):
        import uuid
        note,nid=self.published_thread()
        self.call(self.b,"PUT","notes/"+nid+"/like",liked=True)
        self.thread_reply(self.b,nid,str(uuid.uuid4()))
        note["text"]="Edited note"
        self.call(self.a,"PUT","notes",notes=[note])
        thread=self.call(self.a,"GET","notes/threads")["notes"][0]
        self.assertEqual(thread["likeCount"],1);self.assertEqual(len(thread["replies"]),1)
        self.assertEqual(thread["sourceID"],note["id"])
        self.call(self.a,"PUT","notes",notes=[])
        self.assertEqual(self.service.db.execute("SELECT count(*) FROM journal_likes").fetchone()[0],0)
        self.assertEqual(self.service.db.execute("SELECT count(*) FROM journal_replies").fetchone()[0],0)
        with self.assertRaises(APIError):self.call(self.b,"PUT","notes/"+nid+"/like",liked=True)

    def test_blocked_or_revoked_friends_cannot_interact_or_leave_visible_interactions(self):
        import uuid
        _,nid=self.published_thread()
        self.thread_reply(self.b,nid,str(uuid.uuid4()))
        self.call(self.b,"PUT","notes/"+nid+"/like",liked=True)
        bid=self.snapshot(self.b)["account"]["id"]
        self.call(self.a,"POST","friends/block",id=bid)
        thread=self.call(self.a,"GET","notes/threads")["notes"][0]
        self.assertEqual(thread["replies"],[]);self.assertEqual(thread["likeCount"],0)
        with self.assertRaises(APIError):self.thread_reply(self.b,nid,str(uuid.uuid4()))
        self.call(self.a,"POST","friends/unblock",id=bid)
        self.assertEqual(len(self.call(self.a,"GET","notes/threads")["notes"][0]["replies"]),1)
        self.befriend()
        self.call(self.a,"POST","friends/remove",id=bid)
        with self.assertRaises(APIError):self.call(self.b,"PUT","notes/"+nid+"/like",liked=False)

    def test_shared_reply_validation_and_capacity_keep_existing_thread(self):
        import uuid
        _,nid=self.published_thread()
        for content in ("", " ", "a"*281):
            with self.assertRaises(APIError):self.thread_reply(self.b,nid,str(uuid.uuid4()),content)
        with self.assertRaises(APIError):self.call(self.b,"PUT","notes/"+nid+"/like",liked="true")
        for i in range(50):self.thread_reply(self.b,nid,str(uuid.uuid4()),"Reply "+str(i))
        with self.assertRaises(APIError):self.thread_reply(self.b,nid,str(uuid.uuid4()),"Too many")
        self.assertEqual(len(self.call(self.a,"GET","notes/threads")["notes"][0]["replies"]),50)

    def test_shared_interactions_survive_service_restart_and_commenter_account_deletion(self):
        import uuid, tempfile, sqlite3
        from pathlib import Path
        _,nid=self.published_thread();rid=str(uuid.uuid4())
        self.thread_reply(self.b,nid,rid)
        self.call(self.b,"PUT","notes/"+nid+"/like",liked=True)
        with tempfile.TemporaryDirectory() as directory:
            database=Path(directory)/"plaza.sqlite3"
            with sqlite3.connect(database) as saved:self.service.db.backup(saved)
            saved.close()  # Windows cannot remove a directory with an open SQLite file.
            restarted=PlazaService(str(database),"http://127.0.0.1:8787",now=lambda:self.clock)
            try:
                thread=restarted.handle("GET","/v1/notes/threads",{},self.a)["notes"][0]
                self.assertEqual(thread["likeCount"],1);self.assertEqual(thread["replies"][0]["id"],rid)
            finally:restarted.db.close()
        self.call(self.b,"DELETE","account")
        thread=self.call(self.a,"GET","notes/threads")["notes"][0]
        self.assertEqual(thread["likeCount"],0);self.assertEqual(thread["replies"],[])

    def test_shared_interaction_http_and_two_simultaneous_likes(self):
        import uuid, concurrent.futures
        _,nid=self.published_thread()
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            list(pool.map(lambda token:self.call(token,"PUT","notes/"+nid+"/like",liked=True),[self.a,self.b]))
        self.assertEqual(self.call(self.a,"GET","notes/threads")["notes"][0]["likeCount"],2)
        server=make_server(self.service,port=0)
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        rid=str(uuid.uuid4());appearance=avatar();appearance["id"]=str(uuid.uuid4())
        try:
            request=urllib.request.Request("http://127.0.0.1:"+str(server.server_port)+"/v1/notes/"+nid+"/replies/"+rid,
                method="PUT",data=json.dumps(dict(author=appearance,text="HTTP reply")).encode(),
                headers={"Authorization":"Bearer "+self.b,"Content-Type":"application/json"})
            with urllib.request.urlopen(request) as response:
                self.assertEqual(json.load(response)["replies"][0]["text"],"HTTP reply")
            self.call(self.b,"DELETE","notes/"+nid+"/replies/"+rid)
            self.assertEqual(self.call(self.a,"GET","notes/threads")["notes"][0]["replies"],[])
        finally:server.shutdown();server.server_close();thread.join()

    def test_legacy_note_feed_excludes_own_posts_and_thread_feed_includes_them(self):
        _,nid=self.published_thread()
        self.assertEqual(self.call(self.a,"GET","notes")["notes"],[])
        self.assertEqual(self.call(self.a,"GET","notes/threads")["notes"][0]["id"],nid)
        self.assertEqual(self.call(self.b,"GET","notes")["notes"][0]["id"],nid)

    def test_public_notes_share_independently_of_private_profile_settings(self):
        self.call(self.a, "PUT", "notes", notes=[self.journal_note()])
        self.call(self.a, "PUT", "discord/recipients", discordIDs=["200"])
        self.assertEqual(len(self.call(self.b, "GET", "notes")["notes"]), 1)
        self.assertEqual(self.snapshot(self.b)["friends"], [])
        self.publish(self.a, sharing=False, sharePresence=False, shareActivity=False)
        self.assertEqual(len(self.call(self.b, "GET", "notes")["notes"]), 1)
        self.call(self.a, "PUT", "notes", notes=[])
        self.assertEqual(self.call(self.b, "GET", "notes")["notes"], [])
        self.assertEqual(self.service.db.execute("SELECT count(*) FROM discord_recipients").fetchone()[0], 0)

    def test_shared_notes_http_two_instances_and_large_drawing(self):
        self.befriend()
        server = make_server(self.service, port=0)
        thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
        origin = "http://127.0.0.1:" + str(server.server_port)
        def exchange(token, method, notes=None):
            body = json.dumps(dict(notes=notes)).encode() if notes is not None else None
            request = urllib.request.Request(origin + "/v1/notes", method=method, data=body,
                headers={"Authorization": "Bearer " + token, "Content-Type": "application/json"})
            with urllib.request.urlopen(request) as response:
                return json.load(response)
        try:
            drawing = [dict(points=[dict(x=0.123456789, y=0.987654321)] * 3000, eraser=False)]
            note = self.journal_note(drawing=drawing, drawingDescription="A large drawing")
            self.assertGreater(len(json.dumps(dict(notes=[note]))), 65536)
            self.assertEqual(exchange(self.a, "PUT", [note])["saved"], 1)
            received = exchange(self.b, "GET")["notes"]
            self.assertEqual(received[0]["drawing"], drawing)
            self.assertEqual(exchange(self.c, "GET")["notes"], [])
            note["text"] = "Edited while friend was offline"
            exchange(self.a, "PUT", [note])
            self.assertEqual(exchange(self.b, "GET")["notes"][0]["text"], note["text"])
            exchange(self.a, "PUT", [])
            self.assertEqual(exchange(self.b, "GET")["notes"], [])
        finally:
            server.shutdown(); server.server_close(); thread.join()

    def test_http_transport_rejects_browser_origins_and_bad_sessions(self):
        server = make_server(self.service, port=0)
        thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
        origin = "http://127.0.0.1:" + str(server.server_port)
        try:
            req = urllib.request.Request(origin + "/v1/snapshot", headers={"Authorization": "Bearer " + self.a})
            with urllib.request.urlopen(req) as response:
                self.assertEqual(json.load(response)["account"]["displayName"], "Alice")
                self.assertEqual(response.headers["Cache-Control"], "no-store")
            for headers, expected in [({"Origin": "https://untrusted.example", "Authorization": "Bearer " + self.a}, 403), ({}, 401)]:
                with self.assertRaises(urllib.error.HTTPError) as caught:
                    urllib.request.urlopen(urllib.request.Request(origin + "/v1/snapshot", headers=headers))
                self.assertEqual(caught.exception.code, expected)
        finally:
            server.shutdown(); server.server_close(); thread.join()


if __name__ == "__main__":
    unittest.main()
