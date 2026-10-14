# Discord & Plaza friends: first-release setup

**0.13 testing preview:** the packaged app has the test service preconfigured, signed private updates, and opt-in linked Mii sharing without invitations. See [DISTRIBUTION.md](../DISTRIBUTION.md). The older invitation workflow below remains available for explicit Plaza contacts. Automatic sharing synchronizes publisher-controlled recipient grants from the official SDK; viewer-supplied friend lists never grant access to another publisher’s profile. Grants expire after seven days without sync.

This pilot adds Discord identity linking, a published Mii per account, automatic Discord friend discovery and availability through the official Social SDK, optional Plaza invitations for chosen profiles and app activity, and overhead Plaza notes. Friends using or recently using a matching app gather around its island. The Mac app remains usable offline. Nothing connects until a service address is configured and the user signs in.

## Run as much as possible on each device

Discord & Friends now offers **Connect Discord on This Mac**; Windows offers **Connect Discord on This Computer**. This uses the official SDK’s PKCE flow and local callback instead of routing authorization and token renewal through the hosting Mac. Each device stores only its own authorization in Keychain (Mac) or OS-encrypted storage (Windows). The bot token and OAuth application secret remain on the service. The public Application ID is bundled and can be overridden for a custom application.

The application owner must enable **Public Client** and add exactly `http://127.0.0.1/callback` under OAuth2 in Discord’s Developer Portal once. This is an authentication-configuration change; the code does not change that setting automatically. Existing service sign-in remains available. For the bundled Discord application, Public Client and the localhost callback were enabled and direct Mac sign-in was live-tested on October 14, 2026. Friends also loaded after a full app restart with the Plaza service configured to an unreachable address. Custom Discord applications need their own portal setup; token-expiry renewal and the native Windows sign-in still need live verification.

Once authorized, friends and their Discord availability connect directly from the user’s device, even if the Plaza service is down. A device with direct authorization can also obtain a Plaza session from the updated service using `/v1/auth/direct`. The service verifies the token’s application, scopes, expiry and Discord identity against Discord; it does not store the access token or receive the refresh token. Older services need an update for this route; their existing sign-in still works.

Each device retains authorized discussions locally and can queue likes, replies, reply edits/deletions, profile settings and activity read state during a service outage. Mac caches and queues are encrypted with an account/origin-scoped Keychain key, outside portable plaza exports; Windows discussion state stays in its existing per-account local save and credentials remain separately encrypted. Notes, drafts, rendering, Mii assignments, browsing and search run on the device. Pending delivery survives restart, preserves reply IDs across retries, and coalesces unsent changes. The next successful service poll replaces the cache and removes inaccessible discussions. Seven-day note expiry still applies. A cached discussion cannot reflect another device’s deletion or access revocation until reconnect.

The shared service is still required for delivery between different homes, authorization of published content and optional bot-derived custom statuses/other-game activity. This is local storage with optional shared delivery, not an implemented P2P mesh. The bot cannot move between ordinary users’ devices without distributing its secret. To make shared delivery and the bot work while your Mac is off, run this small service on another always-on host; see the deployment steps below.

## Move the optional service off the Mac

`Server/Dockerfile` and `Server/compose.yaml` package only service source, never the existing `.env`, database, tunnel state or downloads. On an always-on Linux host with Docker Compose:

1. Copy the service source and deployment files. Create a private `.env` from `.env.example`, using the existing Discord Application ID, a stable HTTPS origin for `PLAZA_PUBLIC_URL`, and the bot token only if you need bot features. The OAuth client secret is needed only for legacy service sign-in/refresh.
2. Run `docker compose up -d --build` from the Server directory. SQLite lives in the persistent `plaza-data` volume. The process runs as UID 10001 with a read-only container filesystem; only its data volume and temporary directory are writable.
3. Put your HTTPS reverse proxy in front of `127.0.0.1:8787`. The container port is bound to loopback, so a same-host proxy can reach it. Use edge rate limiting. The pilot also has aggregate request limits behind a proxy, so this configuration is intended for the current small pilot.
4. Preserve the old database using SQLite’s backup API before migration, including existing account IDs, grants, notes and sessions. Stop writers during the final cutover, restore the backup as `/data/plaza.sqlite3` owned by UID 10001, and retain a private rollback copy. Do not run separate writable copies of the database as if they were replicas.
5. Keep the old callback registered, and register the new HTTPS origin plus `/oauth/discord/callback` if retaining legacy sign-in. Point clients and future builds at the new service origin. Credentials and queues are origin-scoped: deliver pending changes before switching origins. Downloads and signed update feeds need their own migration; this container does not copy the Mac’s release files.
6. Check `/health`, sign in, publish a note from one device and reply from another, then repeat with the hosting Mac powered off. Docker deployment requires environment-specific verification and is not claimed as deployed. Direct Mac sign-in and friend loading after restart were verified separately against live Discord with an unreachable Plaza service address.

The container is prepared for deployment; no external host has been selected or provisioned, and the current Mac-hosted service has not been stopped or moved.

## Try the appearance without a service

Build/open `Artifacts/Mac Plaza.app`, then click **Discord & Friends → Preview Sample Friends**. Three clearly labelled sample friends appear in the plaza, with walking Miis, example availability, and overhead notes. Clicking a Mii or note opens its profile. End the preview in Discord & Friends. The preview creates no account and uploads nothing.

## Create a Discord application

1. Create an application at [Discord Developer Portal](https://discord.com/developers/applications). Copy the public Application ID into `DISCORD_CLIENT_ID`.
2. In **OAuth2**, add the exact redirect URL `http://127.0.0.1:8787/oauth/discord/callback` for local testing. For a remote service, register `https://YOUR-HOST/oauth/discord/callback` and use that origin as `PLAZA_PUBLIC_URL`. Do not include a trailing path in the service address.
3. Put the OAuth client secret in the server's `DISCORD_CLIENT_SECRET` environment variable. Never put it in the Mac app, source files, or chat.
4. Open **Social SDK → Getting Started**, enter your developer/contact information, review and accept the SDK terms, then download the macOS SDK. The bundled integration uses version **1.10.19337**. Its headers, macOS framework, and license notices belong under `ThirdParty/DiscordSocialSDK/discord_social_sdk/`. Build scripts embed and sign the framework.
5. For legacy service-managed sign-in, the server performs the confidential OAuth exchange. **Public Client** may remain off if you do not enable direct device sign-in. The app requests `identify openid sdk.social_layer_presence`; no email or message access is requested. After challenge verification, SDK credentials are handed to the Mac and saved in its Keychain. Discord credentials are never written to SQLite. The service issues its own 30-day Plaza session; SDK credentials refresh through an authenticated endpoint that verifies the same Discord identity.

The Mac app uses `ASWebAuthenticationSession`. Discord redirects to the service; the service then redirects to `macplaza://discord-linked`. A single-use five-minute challenge binds completion to the Mac that initiated sign-in. Install/open the built `.app` for this flow, rather than running the executable alone.

## Run locally

The sharing service uses Python 3.9+ and SQLite from the standard library. Python is needed on the server only, not by Mac users.

```sh
cd Server
cp .env.example .env
```

Edit `.env` with the application ID and client secret. This ignored file is a shell environment file; quote its values and do not add commands. Then run:

```sh
set -a
source .env
set +a
python3 server.py
```

The service listens on `127.0.0.1:8787` by default and stores its data in `plaza.sqlite3` in the working directory. The service database, WAL files, environment files, and virtual environments must stay out of source bundles and backups shared with other users. The process creates files with private permissions.

In the Mac app, open **Discord & Friends**, enter `http://127.0.0.1:8787`, and select **Connect Discord**. Complete sign-in. Choose a local Mii, write a note (up to 280 characters), enable sharing, and select **Save Shared Profile**. Editing a local Mii later does not silently upload it; save the shared profile again to publish the edit.

For two different Macs to connect, both must use the same remotely reachable HTTPS service. HTTP is accepted only for local development hosts. A loopback service is not reachable from your friend's Mac.

### Stable Mac-hosted test with a friend

The current preview uses **https://mac-plaza.tail1400d.ts.net**
through Tailscale Funnel to localhost:8787. See [DISTRIBUTION.md](../DISTRIBUTION.md)
for start/stop commands and restart behavior. The registered Discord callback is
that origin plus `/oauth/discord/callback`. The private `.env` uses the same origin.
Tailscale and the Python service must be running on the hosting Mac, which must
stay awake. Testers need only Mac Plaza; no Tailscale install, Python, developer
credentials, or Plaza invitation is required. Squarespace DNS is unchanged.

The dedicated userspace daemon preserves its device identity in private
`Server/.run/tailscale` state. Start/Stop Friend Test.command controls hosting without
changing the system Tailscale VPN. Enable Hosting at Login.command installs a
per-user login agent and moves hosting into `~/Library/Application Support/Mac Plaza Host`
to avoid Desktop privacy restrictions. Its private settings, database and tunnel
state become authoritative there; the original Start/Stop shortcuts forward to it.
Disable Hosting at Login.command removes the agent and preserves the runtime. Only
the hosting Mac needs this setup. Keep the hosting
device and tailnet names unchanged. Existing test installs switch from the retired
Quick Tunnel and GUI-device addresses in version 0.13.2 and need one new Discord sign-in; custom
connection addresses are preserved. Credentials are never moved between origins.

The host can also create expiring ZIP download links for testers without GitHub
accounts using `scripts/share-test-zip.py`; see [DISTRIBUTION.md](../DISTRIBUTION.md).
The private `Server/.downloads` registry is excluded from source bundles. A link
allows only its registered ZIP download; account APIs and update feeds keep their
normal authentication.

## Automatic Discord friends and online status

In the Mac app, connect Discord and authorize the friends presence scopes. Existing identity-only sessions use **Load My Discord Friends**. The official SDK reads the real Discord friend list directly on the Mac and tracks online, idle, do-not-disturb, and offline status. Pending requests and blocked relationships are excluded. Friends need not install Plaza. Random Miis fill in for friends without an authorized shared appearance. Custom status, game, and authored note cards cycle periodically overhead; generic availability is shown only in the native friends list and profiles. Invisible friends appear offline. No invitation is required for this flow.

Discord restricts SDK rich presence to the current application. Other games and custom status text are read through the optional bot’s existing member cache, only for users in a guild shared by the authenticated viewer and the bot. The Mac intersects these observations with its real SDK friend list. **Show custom statuses & games from shared Discord servers** is enabled by default and can be disabled in Discord & Friends. This sends at most 1,000 Discord friend IDs to the viewer’s configured Plaza service per lookup; it does not store the list, game observations, or custom status text in SQLite. No Plaza friendship or linked friend account is required for this bot-visible activity. Game activity visibility follows Discord settings. Current game observations clear when stopped/hidden or when the bot or service disconnects; this adapter does not retain game history. The `/v1/discord/games` response includes `customStatuses` with Discord ID, text, and observation time. Type-4 activity is read only when Discord includes it for a shared guild. Profile privacy (Friends Only, or Friends & Small Servers Only in a server over 200 members) may omit it. Unicode emoji are preserved; server emoji appear as text names. Missing/cleared/hidden statuses replace previous observations, and the Mac discards status observations older than 90 seconds. Older services without this field remain compatible. Chosen Mii appearances, authored notes, and native app activity remain an optional, explicitly shared Plaza feature.

## Optional bot for shared game activity

The bot supplies current Playing activity and server-visible custom status text to Discord friends without Plaza invitations. Both users must share a server containing this bot. The existing explicitly shared Plaza-profile adapter remains available for opted-in observations and availability:



1. In the same Discord application's **Bot** settings, create/reset the bot token and store it only in `DISCORD_BOT_TOKEN` on the server.
2. Enable **Presence Intent** and **Server Members Intent**. Message Content Intent is not used. Member access provides initial availability and removes observations when members leave.
3. Use the application's bot installation link to add it to a Discord server shared by participating friends. Administrator permissions and message-reading permissions are unnecessary.
4. Install the bot dependency into an isolated environment and start the same service there:

```sh
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python server.py
```

5. Each person enables **Share my Discord availability and whether I'm in Plaza** and saves their profile. Availability is refreshed from the bot cache at most every 30 seconds, then fetched by clients every 15 seconds while visible/active.

The bot retains availability and opted-in game activity only in memory. It reads no messages. Custom status text is read only from Discord’s guild-visible presence cache for the viewer’s requested friends. Users outside the bot's servers, a disconnected bot, or disabled sharing produce **Discord status unavailable**. Invisible users appear offline when Discord reports them that way. **In Plaza** is a separate application heartbeat and expires after 75 seconds; it is not proof of Discord availability.

## Gather around apps and games

Enable **Share my current and recently used apps & games**, then save the profile. While Mac Plaza is running and the Mac is awake, it shares the frontmost app's display name and bundle identifier every 15 seconds, including when the plaza window is in the background. No window titles, documents, URLs, or complete application history are collected. Safe mode disables native activity publication. The optional bot also supplies the latest Discord **Playing** activity; it does not collect listening or streaming activity. The same read-only lookup supplies server-visible custom statuses for overhead notes.

For current Discord game activity, enable **Show custom statuses & games from shared Discord servers**. The connection panel reports how many friends the bot can see, how many custom statuses are available, and how many are playing. Add the actual game (not just its launcher) to your homescreen; its label should match the game name Discord displays. Name matching ignores case, spacing, and punctuation but does not guess different game editions or map every game to Steam. If the title differs, rename the app’s shortcut label. Custom Discord status text takes priority over **Playing [game]** and authored notes. Game activity still determines the gathering circle when a custom status is displayed. When the game stops or coverage disappears, the Mii returns to normal gathering. If no custom status, game/app activity, or authored note is available, no overhead card appears. Friend appearances stay stable during game changes.

Friends walk into the circle around a matching app on your current homescreen page. Native app bundle identifiers match first; otherwise an unambiguous normalized app name matches. Current activity takes priority over recent activity, and unavailable/hidden apps never attract the friend to a different app. App switching retargets the walk without teleporting. Native activity becomes recent after it stops being observed; both sources expire after 30 minutes. Only the latest native app and latest Discord game are retained. Disabling the toggle clears those records. Discord disconnect clears game observations immediately.

The preview includes Music, Notes, and Discord activity examples. Add those apps to the homescreen to try the gathering behavior. Profile cards and the accessible friends list identify current versus recent activity.

Discord privileged intent access is subject to [Discord's current review requirements](https://discord.com/blog/updated-requirements-to-how-apps-access-data-in-servers). Check eligibility before growing beyond a small pilot.

## Add and manage friends

1. Alice creates an invitation in Discord & Friends and sends its code to Bob.
2. Bob signs in to the same service, pastes the code, and selects **Send Request**.
3. Alice sees the incoming request and selects **Accept**.
4. Each person's published Mii/note is now available to the other. An unaccepted request never exposes either profile. Codes expire in 24 hours, are single-use, and creating another code revokes the previous one.

The Discord friend list is imported automatically and requires no invitation. These optional Plaza friendships govern access to published appearances, authored notes, and shared app activity. They require explicit acceptance. Accounts support up to 100 friends/pending requests. Friends occupy available crowd slots and all remain accessible in the friends list.

**Hide Mii** affects only this Mac. **Remove** ends sharing between both accounts. **Block** also prevents fresh requests until unblocked; blocked accounts can be managed in Discord & Friends. Turning off Mii sharing hides that published profile on peers' next refresh. **Unlink & Delete Shared Account** deletes the published Mii, note, sessions, invitations, friendships, and block records on the service. Local Miis and journals remain intact.

Discord friends who have not shared an authorized chosen Mii get a random temporary Mii in each viewer's app session. It stays stable across polling, reconnecting after network failures, and hiding/showing. Signing in again or relaunching the app resets these local assignments. A published Mii takes over on the next refresh. Disabling Mii sharing restores the temporary stand-in and removes the private appearance and note. Discord availability comes from the SDK. Additional Plaza heartbeat and app activity require their separate sharing toggles. Temporary Miis are never uploaded, written to an account, or included in portable Plaza exports.

To choose a custom stand-in, click the friend’s Mii or friends-list entry and select **Mii on this Mac**. The chooser is available for Discord friends without an authorized shared Mii. It lists your local Mii library, keeps the friend’s Discord name, status and app activity, and saves only the friend Discord ID and local Mii ID in this Mac’s preferences, scoped to your signed-in Discord account. It survives sign-in, app restart, and service-address changes and is excluded from portable exports. Library edits update the stand-in; deleting the selected Mii falls back to random. **Random Mii (automatic)** clears the saved choice. A friend’s own published Mii takes precedence; the local choice resumes if their shared appearance becomes unavailable. One library Mii can represent several friends while each friend keeps a distinct walker.

The snapshot adds an optional `unlinkedFriends` array containing only accepted friends without published Miis, with consent-filtered presence and activity. Existing `friends` records retain their required avatars, so older clients keep working. New clients also accept snapshots from older services, without fallback records.

Discord games observed through the shared-server bot are remembered on the viewer's Mac for two hours after a confirmed stop. Friends do not need a Plaza account or linked Mii: assigned and random stand-ins retain the activity and gather around the matching visible app. A new game replaces the previous game. The local history survives relaunches, is scoped to the viewer's Discord account and service, and is excluded from portable exports. A relaunch or connection gap uses the last known observation conservatively and never renews the two-hour window. Fresh loss of shared-server coverage, friend removal, hiding/blocking, disabling game display, and unlinking clear the applicable history. Only previously observed games can be remembered; hidden Discord activity and unobserved play sessions are not inferred.

Clicking an app shows **Friends around this app**, with each rendered friend's Mii, name, and **Playing now**, **Using now**, **Recently played**, or **Recently used** plus elapsed time. This list uses the same app matching and expiry as crowd gathering, includes offline friends with remembered games, and hides friend details in Private Presentation. Recently played games also remain eligible for the rotating homescreen's installed-game selection during the two-hour window.

Overhead cards follow animated heads in both renderers. A current visible custom Discord status takes priority, followed by a current Discord game, a shared authored note, and available app activity. Remembered Discord games alternate with the primary text on successive friend-post intervals, using text such as “Exotic_Panda was recently playing Great Game.” Generic online/idle/do-not-disturb/offline and In Plaza bubbles are hidden. Cards avoid launch controls and reserved UI. Cycling pauses on hover or Pause Posts. Private presentation, safe mode, and app previews hide them. The native accessible list exposes friend names, availability, notes, and profiles without relying on the 3D scene.

## Remote pilot deployment

Run one service process with a persistent private SQLite volume, supervised restarts, and an HTTPS reverse proxy. Configure `PLAZA_PUBLIC_URL` as the external HTTPS origin and register its exact callback with Discord. Use a secret manager or a private environment file for both Discord secrets. Keep the default loopback bind behind the proxy; `PLAZA_BIND` and `PORT` can be set explicitly if required by the host.

Disable query-string/access logging for `/oauth/discord/callback` at the proxy so OAuth codes never enter logs. Do not log Authorization headers, request bodies, or invitation codes. Apply request size limits and per-client rate limits at the proxy; the included limiter is a small-service safeguard and sees the proxy's address. `/health` returns `{"ok": true}` for liveness. SQLite backups contain private profile/account data and need restricted access.

The live pilot uses a registered Discord application and stable Tailscale Funnel address. Automatic SDK discovery has been verified with a real linked account: 224 actual Discord friends loaded without invitations, and online status cards were visually confirmed on the live wallpaper. Complete a two-account pilot before releasing live sharing: sign in, publish, exchange/accept invitations, change availability, opt into activity, switch matching apps, check recent-activity expiry, revoke sharing, block, disconnect the bot, and unlink. A third account must never receive private profiles. Signing/notarization of the Mac app remains part of public distribution.

## Verification

```sh
python3 -m unittest discover -s Server -v
```

Run from the repository root. Tests use an isolated SQLite database and stub Discord identity; the HTTP test opens a temporary loopback listener. No real Discord requests or credentials are used.

Run the normal Swift test suite with the repository's module-cache settings. Set `PLAZA_SOCIAL_QA=1` for native visual QA; it writes `.qa/discord-friend-plaza.png` and `.qa/discord-settings.png`. Graphics tests require macOS graphics service access.

The Social SDK integration follows [Discord’s unified friends guide](https://docs.discord.com/developers/discord-social-sdk/development-guides/creating-a-unified-friends-list), alongside the documented [OAuth authorization-code flow](https://docs.discord.com/developers/topics/oauth2) and [Gateway presence](https://docs.discord.com/developers/events/gateway-events#presence-update).

Bot visibility regression tests (requires `Server/requirements.txt`):

```sh
cd Server
.venv/bin/python -B -m unittest -v test_server.py test_presence_bot.py
```

These cover shared guild membership, exclusion of other servers/listening/offline observations, stop/disconnect clearing, authenticated viewer identity, blocked profiles, request limits, and activity lookup without invitations.


## Shared journal notes (0.15)

Authenticated `PUT /v1/notes` atomically replaces only the caller’s public notes (up to 200, 60,000 drawing points total). Empty replacements retract all notes. `GET /v1/notes` returns up to 300 recent notes from the existing authorized friend audience, honoring blocks and expired/revoked Discord grants. Drawings and author appearances are validated; author/note UUIDs are scoped to the authenticated publisher. The service stores only the public projection, with no private replies, drafts, bookmarks or launch paths. Journal requests allow up to 4 MB; other endpoints retain their existing request limits. A failed validation leaves the previous publication intact. Existing databases gain a journal_notes table at startup.

Public-note audiences are independent of profile sharing. Publishing any public notes enables that account’s journal audience; retracting all notes clears journal-only grants. Saving a private profile does not revoke public notes. No existing private journal is uploaded until its owner marks notes public.


## Shared interactions (0.16)

`GET /v1/notes/threads` includes the caller’s own public notes as well as friend notes, with validated `sourceID`, `likeCount`, viewer-specific `liked`, and shared `replies`. The legacy `GET /v1/notes` continues to exclude own notes for older clients. Authenticated `PUT /v1/notes/<note UUID>/like` sets an explicit boolean `liked` (one row per account). `PUT /v1/notes/<note UUID>/replies/<reply UUID>` creates or edits an idempotent text/Mii reply; `DELETE` removes it. Authors may edit/delete their own replies, and note publishers may delete replies on their own notes. Every operation checks the current publisher-granted audience and blocks. Request-supplied owner IDs and dates cannot override the authenticated actor or server timestamp.

Journal publication now upserts retained note rows and deletes only retracted notes, preserving likes/replies during edits and reconnects. Retraction/account deletion cascades related data. Replies are capped at 50 per note and 2,000 per author; likes at 10,000 per note. Snapshot totals remain bounded at 300 notes, 2,000 replies, 60,000 drawing points and 3.5 MB. No private local replies are uploaded.


## Note activity (0.17)

`GET /v1/notes/activity` returns up to 200 recent visible events, their unread count and latest ID. Only new friend likes/replies on the authenticated account’s notes create events. Retry duplicates and edits do not create new notifications. `PUT /v1/notes/activity/read` accepts up to 200 explicit integer IDs and marks only the caller’s rows read; new arrivals outside those IDs stay unread. Blocks/revoked audiences are checked on every read. Unlike, reply deletion, note retraction and account deletion withdraw/cascade their events. Read state persists in the service’s journal_activity table, separately from Mac plaza saves.

**Public journal identity (0.19):** Note/reply responses include server-authenticated `displayName` and note `discordID`. The legacy `author.name` contains the Discord name truncated to the 24-character Mii limit; updated clients render the full separate display name. The author Mii uses the account’s stable `avatar_id`, avoiding duplicate visitors. `PUT /v1/notes` optionally accepts `primaryAvatar`; sanitized appearance is stored in `accounts.journal_avatar` only while public notes remain. Older clients preserve an already supplied primary appearance. Reads project identities onto existing payloads without rewriting saved notes or discussions. Private profile avatars are never used to infer a public primary. Verified Discord authorization refresh also refreshes the linked display name.

### Note retention

Posted notes expire seven 24-hour days after their original creation, including
Miiverse posts and all associated replies, likes and activity. Cleanup runs on
requests and once per minute while idle, using an indexed creation-time query.
Edits preserve the original timestamp, future client dates are clamped to receipt
time, and expired uploads are discarded. SQLite reuses freed pages automatically.
Drafts and independent profile messages are outside this policy.


### Public Miiverse audiences

Each published note carries `audience: "public"` or `"friends"`. Missing audience preserves the legacy friends-only behavior. Private notes are never uploaded. Public feed reads and likes/replies require an authenticated Plaza session established by verified Discord sign-in; the server supplies author names and IDs from that account. A public post does not expose friends-only posts by the same author. All read/action paths check each post and bilateral blocks. Changing a post to friends-only revokes unrelated accounts immediately on the service; making it private or deleting it retracts the remote thread. Existing copies previously viewed while public cannot be recalled from someone else's computer. Feeds remain bounded to 300 posts, 60,000 drawing points, 2,000 replies and 3.5 MB, with seven-day retention. Public posters can be blocked without a prior friendship.

Run `python3 -B -m unittest discover -s Server` from the repository root. `test_public_miiverse.py` covers unrelated users, legacy privacy, audience changes, verified names, blocking, bounds and HTTP authentication.
