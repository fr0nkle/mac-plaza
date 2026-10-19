# Delivering Windows preview updates

Ordinary pushes to `windows` run tests and never update installed users. An explicit
`windows-v<package.json version>` tag runs Windows contract tests, builds the native
bridge, packages Setup/ZIP/source, and tests an installed older baseline upgrading
manually and automatically. Only after those checks pass does GitHub publish an
UNTESTED prerelease plus unsigned `windows-update-candidate.json` metadata.

Complete each release on the existing signing Mac. The production signing key
stays in the macOS Keychain account `macplaza-updates`; it is never uploaded to
GitHub or written to a file. No self-hosted signing runner exists. The final local
signing and Sites publication steps are deliberate requirements, not an unattended
GitHub job. The Mac release scripts, Sparkle feed and signing settings are unchanged.

1. Bump `Windows/package.json` and testing notes; commit/push `windows`, then push
   `windows-v<version>`. Wait for the tag workflow to succeed.
2. Download that published release's installer, portable ZIP, source ZIP and
   `windows-update-candidate.json` with `gh release download`. Save the exact REST
   metadata with `gh api repos/fr0nkle/mac-plaza/releases/tags/windows-v<version>`.
3. From Windows/, prepare the signed feed using existing local tooling:

   ```sh
   node scripts/publish-update.cjs --assets /absolute/release-assets \
     --release /absolute/release.json --site /absolute/Plaza-Site-checkout \
     --signer /absolute/existing/ThirdParty/Sparkle/bin/sign_update
   ```

   This verifies all three downloaded artifacts against GitHub's uploaded digests,
   pins platform/channel/version/installer URL, refuses downgrade or same-version
   replacement, signs only metadata, and verifies against the public key shipped
   in the app. It writes only `dist/windows-preview-update.json` in the existing
   Plaza Site and an identical public release attachment in the assets folder.
4. Publish the Site with the Sites source helper and native save/deploy workflow,
   preserving its project ID and Mac downloads. Upload the signed metadata to the
   corresponding GitHub release for auditing. Verify the live feed with the
   shipping `updates.cjs` manifest validator and the published installer checksum.

The preview app reads only
`https://plaza.squidproductions.org/windows-preview-update.json` and accepts signed
`channel: preview`, Windows x64 installers with strictly newer numeric versions.
It does not follow GitHub's Latest release, a Mac appcast, or the legacy Windows
stable URL. A future stable app/feed must use a separate channel; do not repoint
preview users silently or publish previews to a stable feed.

Setup builds check after startup and every six hours unless checks are disabled.
They show an in-app availability indicator and verified download/install controls.
Automatic downloading/installation is opt-in; ready updates install on the next
launch or through Restart and Install. Portable ZIP users update manually. Failed
installation attempts require an explicit retry. NSIS preserves app data, Miis,
notes, settings and imported resources. Device-specific Windows acceptance remains
separate from the ephemeral CI installer fixture and automated protocol tests.

If fully unattended local signing/publication is desired later, obtain approval
before adding a persistent runner, exporting a key or creating service credentials.
Do not weaken signature validation to bypass that infrastructure requirement.
