# Private friend testing — Mac Plaza 0.13

The repository and GitHub releases are private at https://github.com/fr0nkle/mac-plaza.
Send `Artifacts/Mac-Plaza-0.13.0.dmg` to your tester. It contains the installer,
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

## Keep the Mac-hosted service available

The current test uses an HTTPS Quick Tunnel to the service on localhost:8787.
The public origin is embedded in `scripts/Info.plist`; a fresh install needs no
address entry. Advanced connection settings allow changing it. Credentials remain
in `Server/.env` and Keychain and never enter the repository or installer.

Keep this Mac awake and keep the service and tunnel running during the test. A
restarted Quick Tunnel gets a new hostname. Update `PLAZA_PUBLIC_URL` in the private
environment, the exact Discord callback, and the client service address together.
Changing the service address requires signing in again; sessions are scoped by origin.
Do not use a CNAME pointing your domain at a temporary tunnel: that does not provide
a certificate or a persistent route for your custom hostname.

Your Squarespace domain can later provide `plaza.squidproductions.org` for the API
and updates. A domain is an address, not a running Python/Discord host. Use a stable
HTTPS hosting destination, or a named tunnel configured for a domain/zone supported
by your tunnel provider. Follow the provider's exact DNS records in Squarespace;
do not replace the website or email records. This testing release makes no DNS changes.

## Publish a new private update

1. Increment both version and build in `scripts/Info.plist` (build must increase).
2. Write `scripts/release-notes/VERSION.md`.
3. Run the focused Swift tests and `Server/.venv/bin/python -B -m unittest discover -s Server`.
4. Run `zsh scripts/build-app.sh`, `zsh scripts/package-release.sh`, and
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
