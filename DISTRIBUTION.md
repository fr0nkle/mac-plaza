# Private friend testing — Mac Plaza 0.13

The repository and GitHub releases are private at https://github.com/fr0nkle/mac-plaza.
Send `Artifacts/Mac-Plaza-0.13.3.dmg` to your tester. It contains the installer,
the app for drag-to-Applications installation, instructions, and corresponding source.
The tester needs an Apple silicon Mac and macOS 15 or later. They do not need Python,
GitHub, Developer Portal access, bot tokens, or a Plaza invitation code.

## Tester setup

1. Quit older copies. Install the app in Applications and open that copy.
2. Connect Discord and approve identity/friends authorization in Discord.
3. Select or create a Mii. Enable **Share my chosen Mii and note with my Discord friends**,
   then **Save Shared Profile**. Both people do this to see each other's chosen Miis.
4. For custom statuses and other games, share a Discord server with the existing Plaza
   bot. An administrator can use **Add Plaza bot to a shared Discord server…** once.
5. Automatic checks are enabled after sign-in. Automatic download/installation is enabled by default
   and can be turned off in Preferences. **Check for Updates…** is also in the app menu.

This build is ad-hoc signed, not Developer ID signed or Apple notarized. macOS may
require the recipient to explicitly approve the downloaded app or installer in
Privacy & Security. This cannot be made prompt-free without Apple distribution
credentials. Do not disable Gatekeeper. Original Wii U resources remain optional
local imports; the built-in renderer works immediately.

## Private download without a GitHub account

To share a prepared friend-test ZIP through the running Plaza service:

```sh
python3 -B scripts/share-test-zip.py /path/to/Friend-Test.zip --days 7
```

This copies that ZIP into the active runtime's private `Server/.downloads` folder
and returns an unguessable HTTPS download URL with an expiry. Anyone given the link
can download that file without signing in; it does not grant Plaza account access
or access to GitHub, credentials, other files, or the authenticated update feed.
Keep the URL private and send it only to your tester. Links default to seven days,
can last 1–30 days, and survive service restarts until expiry or revocation.
The hosting Mac must remain online. Browser downloads support resuming.

To revoke a link immediately:

```sh
python3 -B scripts/share-test-zip.py --revoke 'PASTE-THE-DOWNLOAD-URL-HERE'
```

The download route serves only explicitly registered ZIP copies, with no directory
listing. Records store hashes of the random tokens; access logs are suppressed and
responses are attachments with `private, no-store` caching and `no-referrer` policy.
Private ZIPs and token records never enter Git or corresponding-source packages.

## Keep the Mac-hosted service available

The test service is available at **https://mac-plaza.tail1400d.ts.net**.
Tailscale Funnel forwards only this Mac's localhost:8787 service over HTTPS. A
separate Homebrew userspace daemon named **mac-plaza** hosts the route; the regular
Tailscale app and its VPN settings are independent. Keep the dedicated device and
tailnet DNS names unchanged. Login hosting stores its private runtime in
**~/Library/Application Support/Mac Plaza Host**. Preserve its
**Server/.run/tailscale** state: it holds the device identity and HTTPS configuration. Never put that
directory in source archives or share it. Your friend needs no Tailscale installation.

A fresh install needs no address entry. Version 0.13.2 replaces the retired developer
Quick Tunnel and GUI-device addresses in saved preferences, preserving custom
addresses. Install this DMG once when moving from an earlier endpoint. Existing
users connect Discord once at the new address; credentials remain scoped to their
original Keychain origin. Custom friend Mii assignments survive the move.

On the hosting Mac, double-click **Server/Enable Hosting at Login.command** once.
This installs the per-user `org.squidproductions.macplaza.host` LaunchAgent in
`~/Library/LaunchAgents`, starts hosting now, and starts it automatically at each
login. It runs the private userspace daemon, local service, private GitHub release
watcher and awake helper, reusing recorded running processes. If networking is
still starting, launchd retries unsuccessful starts at 30-second intervals.
Startup logs stay private in
`~/Library/Application Support/Mac Plaza Host/Server/.run/login-start*.log`.
The agent runs a private runtime copy outside Desktop privacy protection; it needs
no Full Disk Access. Allow its background item in macOS Settings if prompted.
The agent never changes the system VPN and is only for the developer's hosting Mac;
testers do not install it. See Apple's [LaunchAgent documentation](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html).

**Server/Disable Hosting at Login.command** removes the login agent without
interrupting already running hosting processes. **Server/Start Friend Test.command**
still works for manual starts.
Double-click **Server/Stop Friend Test.command** to stop those recorded processes
and disable only the dedicated Plaza HTTPS route. It also stops login retries for
the current session; automatic startup resumes at the next login unless disabled.
Your database and device identity are preserved. Keep this Mac powered on, online,
and with its lid open during tests; the awake helper does not override shutdown
or lid-close sleep.

The first enable migrates the existing database, private settings, current update
assets, and authorized tunnel identity into Application Support. That runtime's
`Server/.env`, database, `.updates` and `.run/tailscale` are then authoritative;
the old project copies are retained as migration backups and no longer serve users.
The original Start/Stop shortcuts forward to the runtime using the private
`Server/.run/hosting-runtime.json` marker. Disabling login startup leaves this
runtime intact. Re-enabling refreshes helper code while preserving its active data.
After changing hosting code/dependencies in this checkout, run Enable again to
refresh the runtime. Private releases published to GitHub are fetched there by its
release watcher. This host-only change needs no new installer on your friend's Mac.

The controls require the existing Python environment, private `.env`, Homebrew
Tailscale formula, and authorized device state. If restoring onto another Mac or
recovering lost device state, authorize the dedicated node from the runtime root:

```sh
cd "$HOME/Library/Application Support/Mac Plaza Host"
/opt/homebrew/bin/tailscale --socket="$PWD/Server/.run/tailscale/tailscaled.sock" up --hostname=mac-plaza --accept-dns=false --accept-routes=false
/opt/homebrew/bin/tailscale --socket="$PWD/Server/.run/tailscale/tailscaled.sock" funnel --bg --https=443 http://127.0.0.1:8787
```

The start control launches the daemon before requesting authorization. Complete
any device/Funnel approvals in Tailscale yourself. If the assigned hostname changes,
update Discord's exact callback, `PLAZA_PUBLIC_URL`, and the app's bundled endpoint
before distributing another build. Do not register a second device under a duplicate
name and assume it will receive the same address. The hostname is public and appears
in certificate logs.

Credentials remain in the active runtime’s private `Server/.env` and Keychain and
never enter the repository or installer. The old Cloudflare Quick Tunnel is no longer required. Tailscale Funnel
is a beta feature with bandwidth limits, so this remains a friend-testing service,
not an uptime-guaranteed production host.

Your Squarespace domain can later provide `plaza.squidproductions.org` for the API
and updates. A domain is an address, not a running Python/Discord host. Use a stable
HTTPS hosting destination, or a named tunnel configured for a domain/zone supported
by your tunnel provider. Follow the provider's exact DNS records in Squarespace;
do not replace the website or email records. This testing release makes no DNS changes.

## Publish a new private update

1. Increment both version and build in `scripts/Info.plist` (build must increase).
2. Write `scripts/release-notes/VERSION.md`.
3. Run the focused Swift tests and `Server/.venv/bin/python -B -m unittest discover -s Server`.
4. Run `PLAZA_DISTRIBUTION=1 zsh scripts/build-app.sh`, `zsh scripts/package-release.sh`, and
   `zsh scripts/build-installer.sh`.
5. Commit and push the tested source to the private repository.
6. Run `zsh scripts/publish-release.sh`. It signs the app ZIP with the
   `macplaza-updates` Ed25519 key in this Mac's Keychain, stages it locally,
   and uploads the installer, app, source, and release manifest to a private
   GitHub prerelease. The script refuses a public repository.

For releases uploaded from another machine, run `python3 scripts/sync-private-release.py`
on the hosting Mac. `zsh scripts/watch-private-releases.sh` checks every minute while
running. It authenticates to private GitHub locally, checks archive hashes and the
update signature, and stages assets before atomically replacing the feed manifest.
No GitHub credential goes to testers. The service generates a same-origin Sparkle
appcast and requires a live Plaza session for the feed and archives. Leaving the
source repository private does not withhold corresponding source from recipients:
each installer DMG includes its source ZIP and dependency notices.

The update feed is ready for future versions; installing a version newer than the
current release requires publishing that version. Git push alone does not build or
publish an executable release. Releases are intentionally built and signed on this
Mac rather than putting signing keys in GitHub or a self-hosted Actions runner.

## Apple signing when ready

Enroll in Apple's Developer Program. In Xcode/Keychain create **Developer ID Application**
and **Developer ID Installer** identities. Do not send private keys/passwords in chat.

```sh
PLAZA_SIGN_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' zsh scripts/build-app.sh
zsh scripts/package-release.sh
PLAZA_INSTALLER_IDENTITY='Developer ID Installer: YOUR NAME (TEAMID)' zsh scripts/build-installer.sh
xcrun notarytool store-credentials MacPlazaNotary
xcrun notarytool submit Artifacts/Mac-Plaza-VERSION.dmg --keychain-profile MacPlazaNotary --wait
xcrun stapler staple Artifacts/Mac-Plaza-VERSION.dmg
```

Notarize/staple the app as well before creating the final app update ZIP; regenerate
the ZIP, source, installer and signed manifest after stapling. Preserve the bundle
identifier and update public key across releases. Back up the update-signing key
securely; it is never included in source or artifacts. Test a downloaded quarantined
installer on another Mac, and an actual old-to-new update, before public distribution.

## Sharing permissions

The opt-in authorizes this Mac to synchronize the publisher's current official SDK
friend IDs as recipients of that publisher's Mii and note. The service stores those
recipient grants; a viewer's claimed friend list never authorizes access to someone
else's Mii. Removing a Discord friend replaces the grants on the next successful SDK
sync. Grants expire after seven days without a sync. Turning off sharing and saving
revokes grants immediately on the service; viewers refresh approximately every
15 seconds. Existing explicit Plaza friendships remain supported for older clients.
Blocking takes precedence over both sharing paths. Removing an automatic shared
profile also blocks that account to prevent it reappearing; unblock from Discord & Friends.

Status/game observations remain in memory. Native app activity, notes and appearances
keep their separate sharing controls. Portable plaza exports contain no credentials
or recipient grants. A live two-person test is still needed to confirm the friend's
Discord authorization, chosen appearance, game visibility and installer behavior.

## Download page and licensed releases

The public page is hosted separately at plaza.squidproductions.org. The app service
and downloads remain on the hosting Mac. GitHub stays private. The page uses the
public `/releases/latest.json` metadata and permanent `/releases/download/installer`
and `/releases/download/source` routes, so subsequent releases keep the same links.
These routes publish only explicitly staged release files; normal account APIs and
private Sparkle updates still require their existing authentication.

`publish-release.sh` stages the current installer/source after uploading the private
release. The runtime release watcher stages downloads for later private releases
after verifying ZIP signatures and archive/installer checksums. To restage locally,
run `python3 scripts/stage-public-release.py` after preparing the release manifest.

Original code uses the MIT license. Build with PLAZA_DISTRIBUTION=1 to exclude local
Nintendo audio; source packaging always excludes those recordings and the standalone
Discord SDK. Local files remain on the developer's Mac. See LICENSING.md.
