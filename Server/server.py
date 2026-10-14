"""Mac Plaza pilot service. OAuth identity, explicit friendships, and shared Miis.

Run behind an HTTPS reverse proxy for a remote deployment. No Discord user tokens
are persisted. The optional bot records opted-in availability and game activity, never messages/status text.
"""
import base64
import hashlib
import hmac
import json
import math
import os
import secrets
import sqlite3
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from datetime import datetime
from updates import ReleaseStore
from downloads import DownloadStore, byte_range
from public_releases import current as public_release
from collections import defaultdict, deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


NOTE_RETENTION_SECONDS = 7 * 24 * 60 * 60


class APIError(Exception):
    def __init__(self, message, status=400):
        super().__init__(message)
        self.status = status


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


def challenge(verifier):
    return base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()


def text(value, maximum, minimum=0):
    if not isinstance(value, str) or not minimum <= len(value) <= maximum:
        raise APIError("Text is empty or exceeds its limit.")
    if any(ord(c) < 32 and c not in "\n\t" for c in value):
        raise APIError("Text contains unsupported control characters.")
    return value


def boolean(value):
    if not isinstance(value, bool):
        raise APIError("Expected a boolean setting.")
    return value


def bounded(value, maximum, integer=False):
    if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value):
        raise APIError("Invalid character feature.")
    if not 0 <= value <= maximum or (integer and not isinstance(value, int)):
        raise APIError("Character feature is outside its supported range.")
    return value


def validated_avatar(value, avatar_id):
    if not isinstance(value, dict) or not isinstance(value.get("features"), dict):
        raise APIError("Choose a valid Mii to publish.")
    result = {"id": avatar_id, "name": text(value.get("name"), 24, 1).strip()}
    if not result["name"]:
        raise APIError("A Mii needs a name.")
    for key, limit in {"skin": 5, "hair": 131, "hairColor": 7, "eyes": 59, "brows": 23,
                       "nose": 17, "mouth": 35, "face": 11, "outfit": 11}.items():
        result[key] = bounded(value.get(key), limit, True)
    for key in ["eyeSpacing", "featureHeight", "height", "build"]:
        result[key] = bounded(value.get(key), 1)
    for key in ["glasses", "beard"]:
        result[key] = boolean(value.get(key))
    source = value["features"]
    features = {}
    for key, limit in {"eyeColor": 5, "browColor": 7, "mouthColor": 4, "glassesType": 8,
                       "glassesColor": 5, "mustache": 5, "beardType": 5, "facialHairColor": 7,
                       "wrinkles": 11, "makeup": 11, "gender": 1}.items():
        features[key] = bounded(source.get(key), limit, True)
    for key in ["eyeSize", "eyeStretch", "eyeRotation", "eyeY", "browSize", "browStretch",
                "browRotation", "browSpacing", "browY", "noseSize", "noseY", "mouthSize",
                "mouthStretch", "mouthY", "glassesSize", "glassesY", "mustacheSize",
                "mustacheY", "moleSize", "moleX", "moleY"]:
        features[key] = bounded(source.get(key), 1)
    for key in ["mole", "flipHair"]:
        features[key] = boolean(source.get(key))
    # Publish appearance only: birthdays and original creator metadata stay local.
    features.update(birthMonth=0, birthDay=0, creator="", favorite=False, allowCopying=False, sharing=True)
    result["features"] = features
    return result


def validated_journal_note(value, owner):
    if not isinstance(value, dict):
        raise APIError("Invalid shared note.")
    try:
        local_id = str(uuid.UUID(value.get("id", "")))
        author_id = str(uuid.UUID(value["author"]["id"]))
    except (ValueError, TypeError, KeyError, AttributeError):
        raise APIError("Invalid shared note identity.")
    author = validated_avatar(value["author"], str(uuid.uuid5(uuid.UUID(owner), "author:" + author_id)))
    body = text(value.get("text"), 280).strip()
    description = text(value.get("drawingDescription"), 160).strip()
    drawing = value.get("drawing")
    if not isinstance(drawing, list) or len(drawing) > 512:
        raise APIError("Invalid shared drawing.")
    strokes, points = [], 0
    for stroke in drawing:
        if not isinstance(stroke, dict) or not isinstance(stroke.get("points"), list):
            raise APIError("Invalid shared drawing stroke.")
        points += len(stroke["points"])
        if points > 20000:
            raise APIError("Shared drawing exceeds its limit.")
        clean = []
        for point in stroke["points"]:
            if not isinstance(point, dict):
                raise APIError("Invalid shared drawing point.")
            clean.append(dict(x=bounded(point.get("x"), 1), y=bounded(point.get("y"), 1)))
        strokes.append(dict(points=clean, eraser=boolean(stroke.get("eraser"))))
    if (not body and not drawing) or (drawing and not description):
        raise APIError("A shared note needs text or a described drawing.")
    # Missing audience is the legacy friends-only contract, never public.
    audience = value.get("audience", "friends")
    if audience not in ("friends", "public"):
        raise APIError("Choose Public or Friends Only for a shared post.")
    created = bounded(value.get("created"), 100000000000)
    topic = value.get("topic")
    if topic is not None:
        if not isinstance(topic, dict):
            raise APIError("Invalid shared game topic.")
        topic = dict(label=text(topic.get("label"), 60, 1), bundleID=text(topic.get("bundleID"), 250, 1),
                     steamAppID=topic.get("steamAppID"))
        if topic["steamAppID"] is not None:
            if bounded(topic["steamAppID"], 2**32 - 1, integer=True) < 1:
                raise APIError("Invalid Steam game.")
    return dict(id=str(uuid.uuid5(uuid.UUID(owner), "note:" + local_id)), ownerID=owner, sourceID=local_id,
                author=author, text=body, drawing=strokes, drawingDescription=description,
                created=created, topic=topic, audience=audience)


class PlazaService:
    def __init__(self, database, public_url, client_id="", client_secret="", now=time.time):
        parsed = urllib.parse.urlsplit(public_url)
        if (parsed.scheme != "https" and not (parsed.scheme == "http" and parsed.hostname in ("localhost", "127.0.0.1", "::1"))) or parsed.path not in ("", "/") or parsed.query or parsed.fragment or parsed.username:
            raise ValueError("PLAZA_PUBLIC_URL must be an HTTPS origin (HTTP loopback is allowed).")
        self.public_url = public_url.rstrip("/")
        self.client_id, self.client_secret = client_id, client_secret
        self.now = now
        self.lock = threading.RLock()
        self.db = sqlite3.connect(database, check_same_thread=False)
        self.db.row_factory = sqlite3.Row
        self.db.execute("PRAGMA foreign_keys=ON")
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.executescript("""
        CREATE TABLE IF NOT EXISTS accounts (
          id TEXT PRIMARY KEY, discord_id TEXT UNIQUE NOT NULL, name TEXT NOT NULL,
          avatar_id TEXT NOT NULL, avatar TEXT, note TEXT NOT NULL DEFAULT '',
          sharing INTEGER NOT NULL DEFAULT 0, share_presence INTEGER NOT NULL DEFAULT 0,
          seen REAL NOT NULL DEFAULT 0
        );
        CREATE TABLE IF NOT EXISTS sessions (
          hash TEXT PRIMARY KEY, account TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
          expires REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS logins (
          state TEXT PRIMARY KEY, challenge TEXT NOT NULL, expires REAL NOT NULL,
          identity TEXT
        );
        CREATE TABLE IF NOT EXISTS invites (
          hash TEXT PRIMARY KEY, owner TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
          expires REAL NOT NULL
        );
        CREATE TABLE IF NOT EXISTS friendships (
          sender TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
          recipient TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
          accepted INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(sender,recipient)
        );
        CREATE TABLE IF NOT EXISTS blocks (
          owner TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
          target TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE, PRIMARY KEY(owner,target)
        );
        CREATE TABLE IF NOT EXISTS journal_notes (
          owner TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
          id TEXT NOT NULL, payload TEXT NOT NULL, created REAL NOT NULL, PRIMARY KEY(owner,id)
        );
        CREATE INDEX IF NOT EXISTS journal_note_created ON journal_notes(created);
        CREATE TABLE IF NOT EXISTS journal_likes (
          note_owner TEXT NOT NULL, note_id TEXT NOT NULL,
          actor TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
          PRIMARY KEY(note_owner,note_id,actor),
          FOREIGN KEY(note_owner,note_id) REFERENCES journal_notes(owner,id) ON DELETE CASCADE
        );
        CREATE TABLE IF NOT EXISTS journal_replies (
          note_owner TEXT NOT NULL, note_id TEXT NOT NULL, id TEXT NOT NULL,
          actor TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
          payload TEXT NOT NULL, created REAL NOT NULL,
          PRIMARY KEY(note_owner,note_id,id),
          FOREIGN KEY(note_owner,note_id) REFERENCES journal_notes(owner,id) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS journal_reply_actor ON journal_replies(actor);
        CREATE TABLE IF NOT EXISTS journal_activity (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          recipient TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
          actor TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
          note_id TEXT NOT NULL, kind TEXT NOT NULL, ref TEXT NOT NULL,
          created REAL NOT NULL, read INTEGER NOT NULL DEFAULT 0,
          UNIQUE(recipient,actor,note_id,kind,ref),
          FOREIGN KEY(recipient,note_id) REFERENCES journal_notes(owner,id) ON DELETE CASCADE
        );
        CREATE INDEX IF NOT EXISTS journal_activity_recipient ON journal_activity(recipient,id);
        CREATE TABLE IF NOT EXISTS discord_recipients (
          owner TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
          discord_id TEXT NOT NULL, PRIMARY KEY(owner,discord_id)
        );
        """)
        self.presences = {}  # (guild, discord user) -> status; memory only
        self.activities = {}  # Latest Discord game per shared server/user, memory only.
        self.bot_connected = False
        self.discord_games = None  # Bot cache reader; no SDK friends or game history are stored.
        self.sdk_logins = {}  # Short-lived handoff only; Discord tokens are never written to SQLite.
        columns = {r[1] for r in self.db.execute("PRAGMA table_info(accounts)")}
        for name, definition in {"share_activity": "INTEGER NOT NULL DEFAULT 0", "activity_name": "TEXT",
                                 "activity_bundle": "TEXT", "activity_at": "REAL NOT NULL DEFAULT 0",
                                 "activity_active": "INTEGER NOT NULL DEFAULT 0",
                                 "share_discord_friends": "INTEGER NOT NULL DEFAULT 0",
                                 "audience_seen": "REAL NOT NULL DEFAULT 0",
                                 "share_notes": "INTEGER NOT NULL DEFAULT 0", "journal_avatar": "TEXT"}.items():
            if name not in columns:
                self.db.execute("ALTER TABLE accounts ADD COLUMN " + name + " " + definition)
        self.db.commit()
        if "friend_discovery" not in {r[1] for r in self.db.execute("PRAGMA table_info(logins)")}:
            self.db.execute("ALTER TABLE logins ADD COLUMN friend_discovery INTEGER NOT NULL DEFAULT 0")
            self.db.commit()

    def cleanup(self):
        # SQLite reuses freed pages; avoid a costly VACUUM on ordinary requests.
        removed = self.db.execute("DELETE FROM journal_notes WHERE created <= ?", (self.now() - NOTE_RETENTION_SECONDS,)).rowcount
        if removed:
            self.db.execute("""UPDATE accounts SET share_notes=0,journal_avatar=NULL
                WHERE share_notes=1 AND NOT EXISTS (SELECT 1 FROM journal_notes WHERE owner=accounts.id)""")
        for table in ("sessions", "logins", "invites"):
            self.db.execute("DELETE FROM " + table + " WHERE expires <= ?", (self.now(),))
        live = {r[0] for r in self.db.execute("SELECT state FROM logins")}
        self.sdk_logins = {k: v for k, v in self.sdk_logins.items() if k in live}

    def start_login(self, code_challenge, friend_discovery=False):
        text(code_challenge, 43, 43)
        if not all(c.isalnum() and c.isascii() or c in "-_" for c in code_challenge):
            raise APIError("Invalid login challenge.")
        if not self.client_id or not self.client_secret:
            raise APIError("Discord sign-in is not configured on this service.", 503)
        with self.lock, self.db:
            self.cleanup()
            state = secrets.token_urlsafe(32)
            self.db.execute("INSERT INTO logins(state,challenge,expires,identity,friend_discovery) VALUES (?,?,?,NULL,?)", (state, code_challenge, self.now() + 300, friend_discovery))
        scopes = "identify openid sdk.social_layer_presence" if friend_discovery else "identify"
        query = urllib.parse.urlencode(dict(client_id=self.client_id, response_type="code", scope=scopes,
                                           redirect_uri=self.public_url + "/oauth/discord/callback", state=state, prompt="consent"))
        return {"state": state, "authorizeURL": "https://discord.com/oauth2/authorize?" + query}

    def discord_request(self, url, data=None, token=None):
        headers = {"User-Agent": "MacPlaza (Discord account linking)"}
        if data is not None:
            data = urllib.parse.urlencode(data).encode()
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        if token:
            headers["Authorization"] = "Bearer " + token
        req = urllib.request.Request("https://discord.com/api/v10/" + url, data=data, headers=headers)
        with urllib.request.urlopen(req, timeout=15) as response:
            return json.loads(response.read(65536))

    def sdk_credentials(self, tokens, user):
        if "sdk.social_layer_presence" not in tokens.get("scope", "").split():
            raise APIError("Authorize Discord friends access to load your friends.", 403)
        return dict(applicationID=self.client_id, discordID=user["id"],
                    accessToken=text(tokens["access_token"], 4096, 1), refreshToken=text(tokens["refresh_token"], 4096, 1),
                    expiresAt=self.now() + min(604800, max(0, int(tokens["expires_in"]))))

    def discord_identity(self, code, include_friends=False):
        tokens = self.discord_request("oauth2/token", dict(client_id=self.client_id, client_secret=self.client_secret,
                         grant_type="authorization_code", code=code, redirect_uri=self.public_url + "/oauth/discord/callback"))
        keep_token = False
        try:
            user = self.discord_request("users/@me", token=tokens["access_token"])
            identity = {"id": text(user["id"], 24, 1), "name": text(user.get("global_name") or user["username"], 80, 1)}
            if include_friends:
                identity["discordSDK"] = self.sdk_credentials(tokens, user)
                keep_token = True
            return identity
        finally:
            if not keep_token:
                try:
                    self.discord_request("oauth2/token/revoke", dict(client_id=self.client_id, client_secret=self.client_secret,
                        token=tokens["access_token"], token_type_hint="access_token"))
                except (OSError, ValueError):
                    pass

    def callback(self, state, code):
        with self.lock, self.db:
            self.cleanup()
            row = self.db.execute("SELECT * FROM logins WHERE state=?", (state,)).fetchone()
            if not row or row["identity"] is not None:
                raise APIError("Sign-in expired or was already used. Start again.")
            # Claim before contacting Discord so simultaneous callbacks cannot reuse it.
            self.db.execute("UPDATE logins SET identity='{}' WHERE state=?", (state,))
        code = text(code, 512, 1)
        identity = self.discord_identity(code, include_friends=True) if row["friend_discovery"] else self.discord_identity(code)
        with self.lock, self.db:
            if "discordSDK" in identity:
                self.sdk_logins[state] = identity.pop("discordSDK")
            self.db.execute("UPDATE logins SET identity=? WHERE state=? AND expires>?",
                            (json.dumps(identity), state, self.now()))
        return "macplaza://discord-linked?" + urllib.parse.urlencode({"state": state})

    def finish_login(self, state, verifier):
        text(verifier, 128, 43)
        with self.lock, self.db:
            self.cleanup()
            row = self.db.execute("SELECT * FROM logins WHERE state=?", (state,)).fetchone()
            if not row or not hmac.compare_digest(row["challenge"], challenge(verifier)) or not row["identity"]:
                raise APIError("Sign-in expired or could not be verified.", 401)
            identity = json.loads(row["identity"])
            if "id" not in identity:
                raise APIError("Sign-in has not completed.", 409)
            self.db.execute("DELETE FROM logins WHERE state=?", (state,))
            result = self.create_session(identity["id"], identity["name"])
            credentials = self.sdk_logins.pop(state, None)
            if row["friend_discovery"]:
                if not credentials:
                    raise APIError("Discord friends authorization expired. Please connect again.", 401)
                result["discordSDK"] = credentials
            return result

    def create_session(self, discord_id, name):
        """Called only after verified OAuth identity; also used by isolated unit tests."""
        row = self.db.execute("SELECT id FROM accounts WHERE discord_id=?", (discord_id,)).fetchone()
        account = row[0] if row else str(uuid.uuid4())
        self.db.execute("INSERT INTO accounts(id,discord_id,name,avatar_id) VALUES (?,?,?,?) ON CONFLICT(discord_id) DO UPDATE SET name=excluded.name",
                        (account, discord_id, name, str(uuid.uuid4())))
        token = secrets.token_urlsafe(32)
        self.db.execute("INSERT INTO sessions VALUES (?,?,?)", (digest(token), account, self.now() + 30 * 86400))
        return {"token": token}

    def direct_login(self, access_token):
        """Verify a device-obtained OAuth token. No client secret/refresh token is needed."""
        if not self.client_id:
            raise APIError("Discord sign-in is not configured on this service.", 503)
        access_token = text(access_token, 4096, 1)
        authorization = self.discord_request("oauth2/@me", token=access_token)
        scopes = authorization.get("scopes", [])
        if (str(authorization.get("application", {}).get("id", "")) != self.client_id
                or not isinstance(scopes, list)
                or not all(isinstance(scope, str) for scope in scopes)
                or not {"identify", "sdk.social_layer_presence"}.issubset(scopes)):
            raise APIError("Discord authorization does not belong to this Plaza application.", 403)
        try:
            expires = datetime.fromisoformat(authorization["expires"].replace("Z", "+00:00"))
            if expires.tzinfo is None or expires.timestamp() <= self.now():
                raise ValueError()
        except (KeyError, ValueError, TypeError, AttributeError):
            raise APIError("Discord authorization expired. Connect Discord again.", 401)
        user = self.discord_request("users/@me", token=access_token)
        discord_id = text(user.get("id"), 20, 1)
        if not discord_id.isascii() or not discord_id.isdigit() or not 0 < int(discord_id) < 2**64:
            raise APIError("Invalid Discord identity.", 403)
        name = text(user.get("global_name") or user.get("username"), 80, 1)
        with self.lock, self.db:
            self.cleanup()
            return self.create_session(discord_id, name)

    def account(self, token):
        row = self.db.execute("SELECT accounts.* FROM accounts JOIN sessions ON sessions.account=accounts.id WHERE sessions.hash=? AND sessions.expires>?",
                              (digest(token), self.now())).fetchone()
        if not row:
            raise APIError("Your Plaza session expired. Connect Discord again.", 401)
        return row

    def presence(self, discord_id):
        if not self.bot_connected:
            return "unknown"
        states = [s for (_, user), s in self.presences.items() if user == discord_id]
        return next((s for s in ("dnd", "online", "idle", "offline") if s in states), "unknown")

    def set_presence(self, guild, user, status, activity=None):
        with self.lock:
            # Do not retain availability for users who haven't opted in.
            row = self.db.execute("SELECT share_presence,share_activity FROM accounts WHERE discord_id=?", (str(user),)).fetchone()
            key = (str(guild), str(user))
            if row and row["share_presence"] and status in ("online", "idle", "dnd", "offline"):
                self.presences[(str(guild), str(user))] = status
            if row and row["share_activity"]:
                if activity and status in ("online", "idle", "dnd"):
                    self.activities[key] = dict(name=text(activity, 100, 1), bundleID=None, source="discord", active=True, observedAt=self.now())
                elif key in self.activities:
                    self.activities[key]["active"] = False

    def clear_presence(self, guild=None, user=None):
        with self.lock:
            self.presences = {key: value for key, value in self.presences.items()
                              if not ((guild is None or key[0] == str(guild)) and (user is None or key[1] == str(user)))}
            self.activities = {key: value for key, value in self.activities.items()
                              if not ((guild is None or key[0] == str(guild)) and (user is None or key[1] == str(user)))}

    def shared_activities(self, account):
        if not account["share_activity"]:
            return []
        result = []
        if account["activity_name"] and account["activity_at"] > self.now() - 1800:
            result.append(dict(name=account["activity_name"], bundleID=account["activity_bundle"], source="plaza",
                               active=bool(account["activity_active"] and account["activity_at"] > self.now() - 45), observedAt=account["activity_at"]))
        games = [a for (_, user), a in self.activities.items() if user == account["discord_id"] and a["observedAt"] > self.now() - 1800]
        if self.bot_connected and games:
            result.append(max(games, key=lambda a: (a["active"], a["observedAt"])).copy())
        return result

    def blocked(self, a, b):
        return self.db.execute("SELECT 1 FROM blocks WHERE (owner=? AND target=?) OR (owner=? AND target=?)", (a, b, b, a)).fetchone()

    def snapshot(self, account):
        me = dict(id=account["id"], displayName=account["name"], avatar=json.loads(account["avatar"]) if account["avatar"] else None,
                  note=account["note"], sharing=bool(account["sharing"]), sharePresence=bool(account["share_presence"]), shareActivity=bool(account["share_activity"]),
                  shareDiscordFriends=bool(account["share_discord_friends"]))
        rows = self.db.execute("SELECT a.*,f.sender,f.recipient,f.accepted FROM friendships f JOIN accounts a ON a.id=CASE WHEN f.sender=? THEN f.recipient ELSE f.sender END WHERE f.sender=? OR f.recipient=? ORDER BY a.id", (account["id"], account["id"], account["id"])).fetchall()
        friends, unlinked, incoming, outgoing = [], [], [], []
        for row in rows:
            if self.blocked(account["id"], row["id"]):
                continue
            brief = dict(id=row["id"], displayName=row["name"])
            if not row["accepted"]:
                (outgoing if row["sender"] == account["id"] else incoming).append(brief)
            else:
                # Keep a management record even when a friend stops publishing.
                brief.update(shared=bool(row["sharing"] and row["avatar"]))
                if row["sharing"] and row["avatar"]:
                    friends.append(dict(id=row["id"], discordID=row["discord_id"], displayName=row["name"], avatar=json.loads(row["avatar"]),
                         note=row["note"], presence=self.presence(row["discord_id"]) if row["share_presence"] else "unknown",
                         plazaOnline=bool(row["share_presence"] and row["seen"] > self.now() - 75), activities=self.shared_activities(row)))
                else:
                    unlinked.append(dict(id=row["id"], discordID=row["discord_id"], displayName=row["name"],
                         presence=self.presence(row["discord_id"]) if row["share_presence"] else "unknown",
                         plazaOnline=bool(row["share_presence"] and row["seen"] > self.now() - 75), activities=self.shared_activities(row)))
        contacts = [dict(id=r["id"], displayName=r["name"]) for r in rows if r["accepted"] and not self.blocked(account["id"], r["id"])]
        # Only the publisher may grant recipients access to their own profile.
        # Never authorize reads from a viewer-supplied list of claimed friends.
        existing = {friend["id"] for friend in friends + unlinked}
        automatic = self.db.execute("""SELECT a.* FROM accounts a JOIN discord_recipients r ON r.owner=a.id
          WHERE r.discord_id=? AND a.id!=? AND a.sharing=1 AND a.share_discord_friends=1
          AND a.avatar IS NOT NULL AND a.audience_seen>? ORDER BY a.id LIMIT 1000""",
          (account["discord_id"], account["id"], self.now() - 7 * 86400)).fetchall()
        for row in automatic:
            if row["id"] in existing or self.blocked(account["id"], row["id"]):
                continue
            friends.append(dict(id=row["id"], discordID=row["discord_id"], displayName=row["name"],
                avatar=json.loads(row["avatar"]), note=row["note"],
                presence=self.presence(row["discord_id"]) if row["share_presence"] else "unknown",
                plazaOnline=bool(row["share_presence"] and row["seen"] > self.now() - 75), activities=self.shared_activities(row)))
        return dict(account=me, friends=friends, unlinkedFriends=unlinked, contacts=contacts, incoming=incoming, outgoing=outgoing)

    def journal_owners(self, account):
        allowed = {account["id"]}
        rows = self.db.execute("""SELECT CASE WHEN sender=? THEN recipient ELSE sender END AS id
            FROM friendships WHERE accepted=1 AND (sender=? OR recipient=?)""",
            (account["id"], account["id"], account["id"])).fetchall()
        allowed.update(row["id"] for row in rows if not self.blocked(account["id"], row["id"]))
        rows = self.db.execute("""SELECT a.id FROM accounts a JOIN discord_recipients r ON r.owner=a.id
            WHERE r.discord_id=? AND a.share_notes=1 AND a.audience_seen>?""",
            (account["discord_id"], self.now() - 7 * 86400)).fetchall()
        allowed.update(row["id"] for row in rows if not self.blocked(account["id"], row["id"]))
        return allowed

    def journal_can_read(self, account, row, allowed=None):
        owner = row["owner"]
        if owner == account["id"]:
            return True
        if self.blocked(account["id"], owner):
            return False
        if json.loads(row["payload"]).get("audience", "friends") == "public":
            return True
        return owner in (self.journal_owners(account) if allowed is None else allowed)

    def journal_identity(self, account, payload):
        result = dict(payload)
        # Replies have no audience field; posts explicitly retain legacy privacy.
        if "drawing" in result: result["audience"] = result.get("audience", "friends")
        appearance = json.loads(account["journal_avatar"]) if account["journal_avatar"] else dict(payload["author"])
        appearance["id"] = account["avatar_id"]
        appearance["name"] = account["name"][:24]
        result.update(author=appearance, displayName=account["name"], discordID=account["discord_id"])
        return result

    def journal_interactions(self, owner, note_id, viewer):
        # Filter both the viewer's and publisher's blocks, even for previously
        # authored replies/likes. Actor identity always comes from the session.
        exclusion = """ AND NOT EXISTS (SELECT 1 FROM blocks b WHERE
          (b.owner=actor AND b.target IN (?,?)) OR (b.target=actor AND b.owner IN (?,?)))"""
        args = (owner, note_id, viewer, owner, viewer, owner)
        likes = self.db.execute("SELECT count(*),coalesce(max(actor=?),0) FROM journal_likes WHERE note_owner=? AND note_id=?" + exclusion,
            (viewer,) + args).fetchone()
        rows = self.db.execute("SELECT r.payload,a.name,a.avatar_id,a.journal_avatar,a.discord_id FROM journal_replies r JOIN accounts a ON a.id=r.actor WHERE note_owner=? AND note_id=?" + exclusion +
            " ORDER BY r.created,r.id LIMIT 50", args).fetchall()
        replies = [self.journal_identity(row, json.loads(row["payload"])) for row in rows]
        return dict(likeCount=likes[0], liked=bool(likes[1]), replies=replies)

    def journal_snapshot(self, account, include_own=False):
        allowed = self.journal_owners(account)
        notes, points, byte_count, replies = [], 0, 0, 0
        placeholders = ",".join("?" for _ in allowed)
        # Filter per post before applying the feed limit. A public post never
        # grants access to another friends-only post by the same publisher.
        rows = self.db.execute("""SELECT owner,id,payload FROM journal_notes
            WHERE (owner IN (""" + placeholders + """) OR json_extract(payload,'$.audience')='public')
            AND (? OR owner!=?) AND NOT EXISTS (SELECT 1 FROM blocks b
              WHERE (b.owner=? AND b.target=journal_notes.owner)
                 OR (b.target=? AND b.owner=journal_notes.owner))
            ORDER BY CASE WHEN owner=? THEN 0 ELSE 1 END,created DESC,id LIMIT 300""",
            tuple(sorted(allowed)) + (include_own, account["id"], account["id"], account["id"], account["id"])).fetchall()
        owners = {owner: self.db.execute("SELECT * FROM accounts WHERE id=?", (owner,)).fetchone()
                  for owner in {row["owner"] for row in rows}}
        for row in rows:
            if not self.journal_can_read(account, row, allowed):
                continue
            note = self.journal_identity(owners[row["owner"]], json.loads(row["payload"]))
            note["isFriend"] = row["owner"] != account["id"] and row["owner"] in allowed
            note.update(self.journal_interactions(row["owner"], row["id"], account["id"]))
            count = sum(len(stroke["points"]) for stroke in note["drawing"])
            size = len(json.dumps(note).encode("utf-8"))
            if points + count <= 60000 and byte_count + size < 3_500_000 and replies + len(note["replies"]) <= 2000:
                notes.append(note); points += count; byte_count += size; replies += len(note["replies"])
        return dict(notes=notes)

    def record_journal_activity(self, recipient, actor, note_id, kind, ref=""):
        if recipient == actor:
            return
        self.db.execute("INSERT OR IGNORE INTO journal_activity(recipient,actor,note_id,kind,ref,created) VALUES (?,?,?,?,?,?)",
                        (recipient,actor,note_id,kind,ref,self.now()))
        self.db.execute("""DELETE FROM journal_activity WHERE recipient=? AND id NOT IN
            (SELECT id FROM journal_activity WHERE recipient=? ORDER BY id DESC LIMIT 200)""", (recipient,recipient))

    def activity_snapshot(self, account):
        rows = self.db.execute("""SELECT e.*,a.name AS actor_name,n.payload AS note_payload
            FROM journal_activity e JOIN accounts a ON a.id=e.actor
            JOIN journal_notes n ON n.owner=e.recipient AND n.id=e.note_id
            WHERE e.recipient=? ORDER BY e.id DESC LIMIT 200""", (account["id"],)).fetchall()
        result = []
        for row in rows:
            actor = row["actor"]
            if self.blocked(account["id"],actor):
                continue
            person = self.db.execute("SELECT * FROM accounts WHERE id=?", (actor,)).fetchone()
            if not self.journal_can_read(person, dict(owner=account["id"], payload=row["note_payload"])):
                continue
            reply, author = None, None
            if row["kind"] == "reply":
                existing = self.db.execute("SELECT payload FROM journal_replies WHERE note_owner=? AND note_id=? AND id=? AND actor=?",
                    (account["id"],row["note_id"],row["ref"],actor)).fetchone()
                if not existing:
                    continue
                person = self.db.execute("SELECT * FROM accounts WHERE id=?", (actor,)).fetchone()
                reply = self.journal_identity(person, json.loads(existing["payload"])); author = reply["author"]
            elif not self.db.execute("SELECT 1 FROM journal_likes WHERE note_owner=? AND note_id=? AND actor=?",
                    (account["id"],row["note_id"],actor)).fetchone():
                continue
            note = json.loads(row["note_payload"])
            result.append(dict(id=row["id"],kind=row["kind"],actorID=actor,
                actorName=row["actor_name"], author=author,
                noteID=row["note_id"],sourceID=note.get("sourceID"),
                noteText=note["text"] or note["drawingDescription"],replyText=reply["text"] if reply else None,
                topic=note.get("topic"),created=row["created"],read=bool(row["read"])))
        return dict(activities=result,unreadCount=sum(not e["read"] for e in result),latestID=max((e["id"] for e in result),default=0))

    def journal_action(self, method, parts, data, account):
        try:
            note_id = str(uuid.UUID(parts[0]))
        except (ValueError, TypeError):
            raise APIError("Note unavailable.", 404)
        row = self.db.execute("SELECT * FROM journal_notes WHERE id=?", (note_id,)).fetchone()
        if not row or not self.journal_can_read(account, row):
            raise APIError("Note unavailable.", 404)
        owner, actor = row["owner"], account["id"]
        if len(parts) == 2 and parts[1] == "like" and method == "PUT":
            if boolean(data.get("liked")):
                count = self.db.execute("SELECT count(*) FROM journal_likes WHERE note_owner=? AND note_id=?", (owner,note_id)).fetchone()[0]
                existing = self.db.execute("SELECT 1 FROM journal_likes WHERE note_owner=? AND note_id=? AND actor=?", (owner,note_id,actor)).fetchone()
                if count >= 10000 and not existing:
                    raise APIError("This note has reached its like limit.")
                self.db.execute("INSERT OR IGNORE INTO journal_likes VALUES (?,?,?)", (owner,note_id,actor))
                if not existing:
                    self.record_journal_activity(owner,actor,note_id,"like")
            else:
                self.db.execute("DELETE FROM journal_likes WHERE note_owner=? AND note_id=? AND actor=?", (owner,note_id,actor))
                self.db.execute("DELETE FROM journal_activity WHERE recipient=? AND note_id=? AND actor=? AND kind='like'",(owner,note_id,actor))
            return self.journal_interactions(owner,note_id,actor)
        if len(parts) == 3 and parts[1] == "replies" and method in ("PUT", "DELETE"):
            try:
                reply_id = str(uuid.UUID(parts[2]))
            except (ValueError,TypeError):
                raise APIError("Invalid reply identity.")
            existing = self.db.execute("SELECT * FROM journal_replies WHERE note_owner=? AND note_id=? AND id=?", (owner,note_id,reply_id)).fetchone()
            if existing and existing["actor"] != actor and not (method == "DELETE" and actor == owner):
                raise APIError("Only the reply's author may edit it.",403)
            if method == "DELETE":
                self.db.execute("DELETE FROM journal_replies WHERE note_owner=? AND note_id=? AND id=?", (owner,note_id,reply_id))
                self.db.execute("DELETE FROM journal_activity WHERE recipient=? AND note_id=? AND ref=? AND kind='reply'",(owner,note_id,reply_id))
            else:
                content = text(data.get("text"),280,1).strip()
                if not content:
                    raise APIError("Write a reply first.")
                try:
                    author_id = str(uuid.UUID(data["author"]["id"]))
                except (KeyError,ValueError,TypeError,AttributeError):
                    raise APIError("Choose a reply Mii.")
                author = validated_avatar(data["author"],str(uuid.uuid5(uuid.UUID(actor),"author:"+author_id)))
                if not existing:
                    total = self.db.execute("SELECT count(*) FROM journal_replies WHERE note_owner=? AND note_id=?",(owner,note_id)).fetchone()[0]
                    own = self.db.execute("SELECT count(*) FROM journal_replies WHERE actor=?",(actor,)).fetchone()[0]
                    if total >= 50 or own >= 2000:
                        raise APIError("The shared reply limit has been reached.")
                created = existing["created"] if existing else self.now()
                payload = dict(id=reply_id,ownerID=actor,author=author,text=content,created=created)
                self.db.execute("""INSERT INTO journal_replies VALUES (?,?,?,?,?,?)
                    ON CONFLICT(note_owner,note_id,id) DO UPDATE SET payload=excluded.payload""",
                    (owner,note_id,reply_id,actor,json.dumps(payload),created))
                if not existing:
                    self.record_journal_activity(owner,actor,note_id,"reply",reply_id)
            return self.journal_interactions(owner,note_id,actor)
        raise APIError("Unknown note action.",404)

    def handle(self, method, path, data, token):
        if method == "GET" and path == "/v1/config":
            return {"discordApplicationID": self.client_id, "directLogin": True}
        if method == "POST" and path == "/v1/auth/direct":
            return self.direct_login(data.get("accessToken"))
        if method == "POST" and path == "/v1/auth/start":
            return self.start_login(data.get("challenge"), boolean(data.get("friendDiscovery", False)))
        if method == "POST" and path == "/v1/auth/finish":
            return self.finish_login(text(data.get("state"), 64, 1), data.get("verifier"))
        if method == "POST" and path == "/v1/discord/games":
            targets = data.get("discordIDs")
            if not isinstance(targets, list) or len(targets) > 1000 or any(
                    not isinstance(value, str) or not value.isascii() or not value.isdigit()
                    or not 1 <= len(value) <= 20 or not 0 < int(value) < 2**64 for value in targets):
                raise APIError("Choose a bounded list of Discord friends.")
            targets = list(dict.fromkeys(targets))
            with self.lock:
                me = self.account(token)
                viewer = me["discord_id"]
                # Existing Plaza blocks still take precedence over bot-visible data.
                targets = [target for target in targets if not self.db.execute(
                    "SELECT 1 FROM accounts a JOIN blocks b ON (b.owner=? AND b.target=a.id) OR (b.target=? AND b.owner=a.id) WHERE a.discord_id=?",
                    (me["id"], me["id"], target)).fetchone()]
                reader = self.discord_games
            if reader is None:
                return dict(state="not-configured", coveredDiscordIDs=[], games=[], customStatuses=[])
            result = reader(viewer, targets)
            if result["state"] != "ready":
                return dict(state="unavailable", coveredDiscordIDs=[], games=[], customStatuses=[])
            allowed = set(targets)
            covered = [value for value in result["coveredDiscordIDs"] if value in allowed]
            games = [dict(discordID=value["discordID"], name=text(value["name"], 100, 1), observedAt=self.now())
                     for value in result["games"] if value["discordID"] in set(covered)]
            statuses = [dict(discordID=value["discordID"], text=text(value["text"], 280, 1), observedAt=self.now())
                        for value in result.get("customStatuses", []) if value["discordID"] in set(covered)]
            return dict(state="ready", coveredDiscordIDs=covered, games=games, customStatuses=statuses)
        with self.lock, self.db:
            self.cleanup()
            me = self.account(token)
            aid = me["id"]
            if method == "POST" and path == "/v1/discord/refresh":
                tokens = self.discord_request("oauth2/token", dict(client_id=self.client_id, client_secret=self.client_secret,
                    grant_type="refresh_token", refresh_token=text(data.get("refreshToken"), 4096, 1)))
                user = self.discord_request("users/@me", token=tokens["access_token"])
                if user["id"] != me["discord_id"]:
                    raise APIError("Discord friends must belong to the linked account.", 403)
                self.db.execute("UPDATE accounts SET name=? WHERE id=?", (text(user.get("global_name") or user.get("username") or me["name"], 80, 1), aid))
                return self.sdk_credentials(tokens, user)
            if method == "PUT" and path == "/v1/notes":
                items = data.get("notes")
                if not isinstance(items, list) or len(items) > 200:
                    raise APIError("Share at most 200 notes.")
                notes = [validated_journal_note(item, aid) for item in items]
                primary = validated_avatar(data["primaryAvatar"], me["avatar_id"]) if data.get("primaryAvatar") is not None else None
                if len({note["id"] for note in notes}) != len(notes) or sum(
                        len(stroke["points"]) for note in notes for stroke in note["drawing"]) > 60000:
                    raise APIError("Duplicate notes or excessive drawing data.")
                # Validate the entire replacement before deleting anything. A
                # single transaction carries edits, private changes and deletions.
                existing_dates = {r[0]: r[1] for r in self.db.execute("SELECT id,created FROM journal_notes WHERE owner=?",(aid,))}
                now = self.now()
                for note in notes:
                    # Edits cannot reset a post's age, and future clocks cannot defer expiry.
                    note["created"] = min(note["created"], existing_dates.get(note["id"], now), now)
                notes = [note for note in notes if note["created"] > now - NOTE_RETENTION_SECONDS]
                existing = set(existing_dates)
                removed = existing - {note["id"] for note in notes}
                self.db.executemany("DELETE FROM journal_notes WHERE owner=? AND id=?",[(aid,value) for value in removed])
                self.db.executemany("""INSERT INTO journal_notes VALUES (?,?,?,?)
                    ON CONFLICT(owner,id) DO UPDATE SET payload=excluded.payload,created=excluded.created""", [
                    (aid, note["id"], json.dumps(note), note["created"]) for note in notes])
                self.db.execute("UPDATE accounts SET share_notes=? WHERE id=?", (bool(notes), aid))
                self.db.execute("UPDATE accounts SET journal_avatar=? WHERE id=?", (json.dumps(primary) if primary and notes else me["journal_avatar"] if notes else None, aid))
                if not notes and not (me["sharing"] and me["share_discord_friends"]):
                    self.db.execute("DELETE FROM discord_recipients WHERE owner=?", (aid,))
                    self.db.execute("UPDATE accounts SET audience_seen=0 WHERE id=?", (aid,))
                return dict(saved=len(notes))
            if method == "GET" and path == "/v1/notes/activity":
                return self.activity_snapshot(me)
            if method == "PUT" and path == "/v1/notes/activity/read":
                ids = data.get("ids")
                if not isinstance(ids,list) or len(ids)>200 or any(type(value) is not int or value<=0 or value>9_000_000_000_000_000 for value in ids):
                    raise APIError("Choose a bounded list of activity IDs.")
                self.db.executemany("UPDATE journal_activity SET read=1 WHERE recipient=? AND id=?",[(aid,value) for value in set(ids)])
                return self.activity_snapshot(me)
            if method == "GET" and path == "/v1/notes/owned":
                # Complete publisher payloads, without the feed's interaction
                # budget. A new device can safely merge before replacement.
                rows = self.db.execute("SELECT payload FROM journal_notes WHERE owner=? ORDER BY created DESC,id", (aid,)).fetchall()
                return dict(notes=[json.loads(row["payload"]) for row in rows])
            if method == "GET" and path == "/v1/notes/threads":
                return self.journal_snapshot(me,include_own=True)
            if path.startswith("/v1/notes/"):
                return self.journal_action(method,path[len("/v1/notes/"):].split("/"),data,me)
            if method == "GET" and path == "/v1/notes":
                return self.journal_snapshot(me)
            if method == "GET" and path == "/v1/snapshot":
                return self.snapshot(me)
            if method == "PUT" and path == "/v1/discord/recipients":
                targets = data.get("discordIDs")
                if not isinstance(targets, list) or len(targets) > 1000 or any(
                    not isinstance(value, str) or not value.isascii() or not value.isdigit()
                    or not 0 < int(value) < 2**64 for value in targets):
                    raise APIError("Choose at most 1,000 Discord recipients.")
                if not me["share_notes"] and not (me["share_discord_friends"] and me["sharing"]):
                    raise APIError("Publish public notes or enable profile sharing first.", 403)
                targets = set(targets) - {me["discord_id"]}
                current = {r[0] for r in self.db.execute("SELECT discord_id FROM discord_recipients WHERE owner=?", (aid,))}
                if current != targets:
                    self.db.execute("DELETE FROM discord_recipients WHERE owner=?", (aid,))
                    self.db.executemany("INSERT INTO discord_recipients VALUES (?,?)", [(aid, value) for value in targets])
                self.db.execute("UPDATE accounts SET audience_seen=? WHERE id=?", (self.now(), aid))
                return {}
            if method == "PUT" and path == "/v1/profile":
                sharing, share_presence = boolean(data.get("sharing")), boolean(data.get("sharePresence"))
                share_activity = boolean(data.get("shareActivity", False))
                avatar = validated_avatar(data["avatar"], me["avatar_id"]) if data.get("avatar") is not None else None
                if sharing and avatar is None:
                    raise APIError("Choose a Mii before enabling sharing.")
                share_discord = boolean(data.get("shareDiscordFriends", False))
                self.db.execute("UPDATE accounts SET avatar=?,note=?,sharing=?,share_presence=?,share_activity=?,share_discord_friends=? WHERE id=?",
                                (json.dumps(avatar) if avatar else None, text(data.get("note"), 280).strip(), sharing, share_presence, share_activity, share_discord, aid))
                if (not share_discord or not sharing) and not me["share_notes"]:
                    self.db.execute("DELETE FROM discord_recipients WHERE owner=?", (aid,))
                    self.db.execute("UPDATE accounts SET audience_seen=0 WHERE id=?", (aid,))
                if not share_presence and not share_activity:
                    self.clear_presence(user=me["discord_id"])
                elif not share_presence:
                    self.presences = {key: value for key, value in self.presences.items() if key[1] != me["discord_id"]}
                if not share_activity:
                    self.db.execute("UPDATE accounts SET activity_name=NULL,activity_bundle=NULL,activity_at=0,activity_active=0 WHERE id=?", (aid,))
                    self.activities = {key: value for key, value in self.activities.items() if key[1] != me["discord_id"]}
                return self.snapshot(self.account(token))
            if method == "POST" and path == "/v1/heartbeat":
                self.db.execute("UPDATE accounts SET seen=? WHERE id=?", (self.now() if boolean(data.get("active")) else 0, aid))
                if me["share_activity"]:
                    application = data.get("application")
                    if application is not None:
                        name = text(application.get("name"), 100, 1)
                        bundle = text(application.get("bundleID"), 250, 1)
                        self.db.execute("UPDATE accounts SET activity_name=?,activity_bundle=?,activity_at=?,activity_active=1 WHERE id=?", (name, bundle, self.now(), aid))
                    else:
                        self.db.execute("UPDATE accounts SET activity_active=0 WHERE id=?", (aid,))
                self.db.execute("UPDATE accounts SET activity_name=NULL,activity_bundle=NULL,activity_at=0,activity_active=0 WHERE activity_at>0 AND activity_at<=?", (self.now() - 1800,))
                self.activities = {key: value for key, value in self.activities.items() if value["observedAt"] > self.now() - 1800}
                return {}
            if method == "POST" and path == "/v1/invites":
                self.db.execute("DELETE FROM invites WHERE owner=?", (aid,))
                code = secrets.token_urlsafe(24)
                self.db.execute("INSERT INTO invites VALUES (?,?,?)", (digest(code), aid, self.now() + 86400))
                return dict(code=code)
            if method == "POST" and path == "/v1/friends/request":
                invite = self.db.execute("SELECT owner FROM invites WHERE hash=? AND expires>?", (digest(text(data.get("code"), 80, 1)), self.now())).fetchone()
                if not invite or invite[0] == aid or self.blocked(aid, invite[0]):
                    raise APIError("Invitation unavailable or expired.", 404)
                other = invite[0]
                if self.db.execute("SELECT 1 FROM friendships WHERE (sender=? AND recipient=?) OR (sender=? AND recipient=?)", (aid, other, other, aid)).fetchone():
                    raise APIError("A friendship or request already exists.", 409)
                for person in (aid, other):
                    if self.db.execute("SELECT count(*) FROM friendships WHERE sender=? OR recipient=?", (person, person)).fetchone()[0] >= 100:
                        raise APIError("This account has reached its 100 friendship/request limit.", 409)
                self.db.execute("INSERT INTO friendships VALUES (?,?,0)", (aid, other))
                self.db.execute("DELETE FROM invites WHERE owner=?", (other,))
                return self.snapshot(me)
            if method == "POST" and path == "/v1/friends/accept":
                other = text(data.get("id"), 36, 36)
                updated = self.db.execute("UPDATE friendships SET accepted=1 WHERE sender=? AND recipient=? AND accepted=0", (other, aid))
                if not updated.rowcount or self.blocked(aid, other):
                    raise APIError("Friend request unavailable.", 404)
                return self.snapshot(me)
            if method == "POST" and path in ("/v1/friends/remove", "/v1/friends/block"):
                other = text(data.get("id"), 36, 36)
                exists = self.db.execute("SELECT 1 FROM friendships WHERE (sender=? AND recipient=?) OR (sender=? AND recipient=?)", (aid, other, other, aid)).fetchone()
                target = self.db.execute("SELECT discord_id FROM accounts WHERE id=?", (other,)).fetchone()
                automatic = target and self.db.execute("SELECT 1 FROM discord_recipients WHERE (owner=? AND discord_id=?) OR (owner=? AND discord_id=?)",
                    (other, me["discord_id"], aid, target[0])).fetchone()
                public_target = path.endswith("block") and target is not None and other != aid
                if not exists and not automatic and not public_target:
                    raise APIError("Friendship unavailable.", 404)
                self.db.execute("DELETE FROM friendships WHERE (sender=? AND recipient=?) OR (sender=? AND recipient=?)", (aid, other, other, aid))
                if path.endswith("block") or automatic:
                    self.db.execute("INSERT OR IGNORE INTO blocks VALUES (?,?)", (aid, other))
                return self.snapshot(me)
            if method == "GET" and path == "/v1/blocks":
                return {"blocks": [dict(id=r["id"], displayName=r["name"]) for r in self.db.execute("SELECT a.id,a.name FROM blocks b JOIN accounts a ON a.id=b.target WHERE b.owner=? ORDER BY a.id", (aid,))]}
            if method == "POST" and path == "/v1/friends/unblock":
                self.db.execute("DELETE FROM blocks WHERE owner=? AND target=?", (aid, text(data.get("id"), 36, 36)))
                return {}
            if method == "POST" and path == "/v1/logout":
                self.db.execute("DELETE FROM sessions WHERE hash=?", (digest(token),))
                self.db.execute("UPDATE accounts SET seen=0 WHERE id=?", (aid,))
                return {}
            if method == "DELETE" and path == "/v1/account":
                self.clear_presence(user=me["discord_id"])
                self.db.execute("DELETE FROM accounts WHERE id=?", (aid,))
                return {}
            raise APIError("Endpoint not found.", 404)


class Handler(BaseHTTPRequestHandler):
    server_version = "MacPlaza"
    def log_message(self, *_):
        pass  # OAuth codes, session tokens, and invite codes must not enter access logs.

    def respond(self, status, payload, headers=None):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def download(self, path):
        try:
            asset, data = DownloadStore(os.environ.get("PLAZA_DOWNLOADS", ".downloads")).resolve(path[len("/download/"):])
            stream = asset.open("rb")
        except OSError:
            raise APIError("Download unavailable or expired.", 404)
        with stream:
            etag = '"' + data["sha256"] + '"'
            # HEAD describes the full representation. If-Range mismatch means full GET.
            requested = self.headers.get("Range") if self.command == "GET" else None
            if self.headers.get("If-Range") not in (None, etag):
                requested = None
            try:
                first, last = byte_range(requested, data["size"])
            except ValueError:
                return self.respond(416, {"error": "Requested range unavailable."},
                                    {"Content-Range": "bytes */" + str(data["size"])})
            self.send_response(206 if requested else 200)
            self.send_header("Content-Type", "application/x-apple-diskimage" if asset.suffix == ".dmg" else "application/zip")
            self.send_header("Content-Disposition", 'attachment; filename="' + data["filename"] + '"')
            self.send_header("Content-Length", str(last - first + 1))
            self.send_header("Cache-Control", "private, no-store")
            self.send_header("Referrer-Policy", "no-referrer")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("Accept-Ranges", "bytes")
            self.send_header("ETag", etag)
            if requested:
                self.send_header("Content-Range", "bytes %d-%d/%d" % (first, last, data["size"]))
            self.end_headers()
            if self.command == "HEAD":
                return
            stream.seek(first)
            remaining = last - first + 1
            try:
                while remaining:
                    chunk = stream.read(min(256 * 1024, remaining))
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    remaining -= len(chunk)
            except OSError:
                pass  # Transfer already began; do not append a JSON error to the ZIP.

    def dispatch(self):
        try:
            self.connection.settimeout(20)
            parsed = urllib.parse.urlsplit(self.path)
            path = parsed.path
            # Bounded per-peer limiter. Proxy deployments must also rate-limit at the edge.
            now = time.monotonic()
            key = (self.client_address[0], "auth" if path.startswith("/v1/auth") else "api")
            with self.server.rate_lock:
                for stale in [k for k, v in self.server.rates.items() if not v or now - v[-1] > 60]:
                    del self.server.rates[stale]
                bucket = self.server.rates[key]
                while bucket and now - bucket[0] > 60:
                    bucket.popleft()
                if len(bucket) >= (12 if key[1] == "auth" else 180):
                    raise APIError("Too many requests. Try again shortly.", 429)
                bucket.append(now)
            if self.command == "GET" and path == "/health":
                return self.respond(200, {"ok": True})
            if self.command == "GET" and path == "/oauth/discord/callback":
                query = urllib.parse.parse_qs(parsed.query)
                location = self.server.service.callback(text(query.get("state", [""])[0], 64, 1), query.get("code", [""])[0])
                return self.respond(302, {}, {"Location": location})
            if self.command in ("GET", "HEAD") and (path == "/releases/latest.json" or path.startswith("/releases/download/")):
                try:
                    release = public_release(os.environ.get("PLAZA_DOWNLOADS", ".downloads"))
                    if path == "/releases/latest.json":
                        files = {key: {**{k: v for k, v in entry.items() if k != "token"},
                                       "path": "/releases/download/" + key}
                                 for key, entry in release["files"].items()}
                        return self.respond(200, dict(version=release["version"], build=release["build"], files=files),
                                            {"Access-Control-Allow-Origin": "*"})
                    key = path[len("/releases/download/"):]
                    if key not in ("installer", "source"):
                        raise APIError("Download unavailable.", 404)
                    return self.download("/download/" + release["files"][key]["token"])
                except (OSError, ValueError, KeyError, TypeError):
                    raise APIError("The testing release is not available yet.", 503)
            if self.headers.get("Origin"):
                raise APIError("Browser API requests are not supported.", 403)
            if self.command in ("GET", "HEAD") and path.startswith("/download/"):
                return self.download(path)
            length = int(self.headers.get("Content-Length", "0"))
            if length < 0 or length > (4_000_000 if path == "/v1/notes" else 65536) or self.headers.get("Transfer-Encoding"):
                raise APIError("Request exceeds the 64 KB limit.", 413)
            data = {}
            if self.command in ("POST", "PUT", "DELETE"):
                if self.headers.get_content_type() != "application/json":
                    raise APIError("Use application/json.", 415)
                data = json.loads(self.rfile.read(length)) if length else {}
                if not isinstance(data, dict):
                    raise APIError("Expected a JSON object.")
            auth = self.headers.get("Authorization", "")
            token = auth[7:] if auth.startswith("Bearer ") else ""
            if self.command == "GET" and path.startswith("/updates/"):
                with self.server.service.lock:
                    self.server.service.account(token)
                store = ReleaseStore(os.environ.get("PLAZA_UPDATES", ".updates"))
                try:
                    if path == "/updates/appcast.xml":
                        body = store.appcast(self.server.service.public_url)
                        self.send_response(200)
                        self.send_header("Content-Type", "application/rss+xml; charset=utf-8")
                        self.send_header("Content-Length", str(len(body)))
                        self.send_header("Cache-Control", "no-store")
                        self.end_headers(); self.wfile.write(body)
                        return
                    manifest = store.manifest()
                    name = path.removeprefix("/updates/") if hasattr(path, "removeprefix") else path[len("/updates/"):]
                    if name not in (manifest["archive"], manifest.get("source")):
                        raise APIError("Release archive unavailable.", 404)
                    archive = store.asset(name)
                    with archive.open("rb") as stream:
                        self.send_response(200)
                        self.send_header("Content-Type", "application/zip")
                        self.send_header("Content-Length", str(archive.stat().st_size))
                        self.send_header("Cache-Control", "private, no-store")
                        self.send_header("X-Content-Type-Options", "nosniff")
                        self.end_headers()
                        while True:
                            chunk = stream.read(256 * 1024)
                            if not chunk: break
                            self.wfile.write(chunk)
                    return
                except (OSError, ValueError, KeyError):
                    raise APIError("No complete testing release is available yet.", 503)
            result = self.server.service.handle(self.command, path, data, token)
            self.respond(200, result)
        except (BrokenPipeError, ConnectionResetError):
            pass  # A cancelled/resumed download must not produce another response.
        except APIError as error:
            self.respond(error.status, {"error": str(error)})
        except (ValueError, KeyError, TypeError):
            self.respond(400, {"error": "Invalid request."})
        except (urllib.error.URLError, TimeoutError):
            self.respond(502, {"error": "Discord is unavailable. Start sign-in again shortly."})
        except Exception:
            self.respond(500, {"error": "The Plaza service could not complete this request."})

    do_GET = do_HEAD = do_POST = do_PUT = do_DELETE = dispatch


class PlazaHTTPServer(ThreadingHTTPServer):
    def service_actions(self):
        now = time.monotonic()
        if now - getattr(self, "last_cleanup", float("-inf")) >= 60:
            with self.service.lock, self.service.db:
                self.service.cleanup()
            self.last_cleanup = now


def make_server(service, host="127.0.0.1", port=8787):
    server = PlazaHTTPServer((host, port), Handler)
    server.daemon_threads = True
    server.service = service
    server.rates, server.rate_lock = defaultdict(deque), threading.Lock()
    return server


if __name__ == "__main__":
    os.umask(0o077)
    service = PlazaService(os.environ.get("PLAZA_DATABASE", "plaza.sqlite3"),
                           os.environ.get("PLAZA_PUBLIC_URL", "http://127.0.0.1:8787"),
                           os.environ.get("DISCORD_CLIENT_ID", ""), os.environ.get("DISCORD_CLIENT_SECRET", ""))
    if os.environ.get("DISCORD_BOT_TOKEN"):
        from presence_bot import start_bot
        start_bot(service, os.environ["DISCORD_BOT_TOKEN"])
    server = make_server(service, os.environ.get("PLAZA_BIND", "127.0.0.1"), int(os.environ.get("PORT", "8787")))
    print("Mac Plaza pilot service listening on port", server.server_port, flush=True)
    server.serve_forever()
