# Discord & Plaza friends: first-release setup

**0.13 private testing:** the packaged app has the test service preconfigured, signed private updates, and opt-in linked Mii sharing without invitations. See [DISTRIBUTION.md](../DISTRIBUTION.md). The older invitation workflow below remains available for explicit Plaza contacts. Automatic sharing synchronizes publisher-controlled recipient grants from the official SDK; viewer-supplied friend lists never grant access to another publisher’s profile. Grants expire after seven days without sync.

This pilot adds Discord identity linking, a published Mii per account, automatic Discord friend discovery and availability through the official Social SDK, optional Plaza invitations for chosen profiles and app activity, and overhead Plaza notes. Friends using or recently using a matching app gather around its island. The Mac app remains usable offline. Nothing connects until a service address is configured and the user signs in.

## Try the appearance without a service

Build/open `Artifacts/Mac Plaza.app`, then click **Discord & Friends → Preview Sample Friends**. Three clearly labelled sample friends appear in the plaza, with walking Miis, example availability, and overhead notes. Clicking a Mii or note opens its profile. End the preview in Discord & Friends. The preview creates no account and uploads nothing.

## Create a Discord application

1. Create an application at [Discord Developer Portal](https://discord.com/developers/applications). Copy the public Application ID into `DISCORD_CLIENT_ID`.
2. In **OAuth2**, add the exact redirect URL `http://127.0.0.1:8787/oauth/discord/callback` for local testing. For a remote service, register `https://YOUR-HOST/oauth/discord/callback` and use that origin as `PLAZA_PUBLIC_URL`. Do not include a trailing path in the service address.
3. Put the OAuth client secret in the server's `DISCORD_CLIENT_SECRET` environment variable. Never put it in the Mac app, source files, or chat.
4. Open **Social SDK → Getting Started**, enter your developer/contact information, review and accept the SDK terms, then download the macOS SDK. The bundled integration uses version **1.10.19337**. Its headers, macOS framework, and license notices belong under `ThirdParty/DiscordSocialSDK/discord_social_sdk/`. Build scripts embed and sign the framework.
5. Keep **Public Client** off. The server performs the confidential OAuth exchange. The app requests `identify openid sdk.social_layer_presence`; no email or message access is requested. After challenge verification, SDK credentials are handed to the Mac and saved in its Keychain. Discord credentials are never written to SQLite. The service issues its own 30-day Plaza session; SDK credentials refresh through an authenticated endpoint that verifies the same Discord identity.

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

### Temporary Mac-hosted test with a friend

Install `cloudflared` from [Cloudflare's official downloads](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/downloads/) (or use the project-local `Server/.tools/cloudflared` if already installed). In a separate terminal, run:

```sh
cloudflared tunnel --no-autoupdate --url http://127.0.0.1:8787 --protocol http2
```

Keep that terminal running. Copy its `https://….trycloudflare.com` origin into `PLAZA_PUBLIC_URL` in `Server/.env`, and register that exact origin plus `/oauth/discord/callback` under Discord's **OAuth2 → Redirects**. Keep **Public Client** off: this service performs the confidential OAuth exchange. Store the client secret and bot token only in the private `.env` file. Then, from the repository root:

```sh
Server/.venv/bin/python Server/run_local.py
```

This loader reads quoted settings without executing shell commands. It uses the existing isolated environment; create it and install `Server/requirements.txt` first if needed. Keep the service and tunnel running, with your Mac awake. Both Macs enter the same public origin in Discord & Friends. The friend needs the built Mac app, not Python or your secrets. Automatic Discord friends and availability need no bot installation or Plaza invitation.

Verify the public origin's `/health` returns `{"ok": true}` before connecting. Stop both processes with Control-C after testing. A restarted Quick Tunnel gets a new hostname: update `.env`, Discord's redirect, and both clients. Local SQLite data remains on your Mac; this temporary route has no uptime guarantee. [Quick Tunnel limitations](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/).

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

Overhead cards follow animated heads in both renderers. A current visible custom Discord status takes priority, followed by a current Discord game, a shared authored note, and available app activity. Generic online/idle/do-not-disturb/offline and In Plaza bubbles are hidden. At most two friend cards appear alongside the existing journal card; cards avoid launch controls, the journal card, and one another. Cycling pauses on hover or Pause Posts. Private presentation, safe mode, and app previews hide them. The native accessible list exposes friend names, availability, notes, and profiles without relying on the 3D scene.

## Remote pilot deployment

Run one service process with a persistent private SQLite volume, supervised restarts, and an HTTPS reverse proxy. Configure `PLAZA_PUBLIC_URL` as the external HTTPS origin and register its exact callback with Discord. Use a secret manager or a private environment file for both Discord secrets. Keep the default loopback bind behind the proxy; `PLAZA_BIND` and `PORT` can be set explicitly if required by the host.

Disable query-string/access logging for `/oauth/discord/callback` at the proxy so OAuth codes never enter logs. Do not log Authorization headers, request bodies, or invitation codes. Apply request size limits and per-client rate limits at the proxy; the included limiter is a small-service safeguard and sees the proxy's address. `/health` returns `{"ok": true}` for liveness. SQLite backups contain private profile/account data and need restricted access.

The live pilot uses a registered Discord application and temporary HTTPS tunnel. Automatic SDK discovery has been verified with a real linked account: 224 actual Discord friends loaded without invitations, and online status cards were visually confirmed on the live wallpaper. Complete a two-account pilot before releasing live sharing: sign in, publish, exchange/accept invitations, change availability, opt into activity, switch matching apps, check recent-activity expiry, revoke sharing, block, disconnect the bot, and unlink. A third account must never receive private profiles. Signing/notarization of the Mac app remains part of public distribution.

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
