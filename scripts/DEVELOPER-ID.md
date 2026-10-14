# Developer ID releases

Public direct-download releases use Developer ID Application and Developer ID
Installer certificates from the same enrolled Apple developer team. The build
submits the app and installer disk image to Apple, staples the accepted tickets,
and verifies Gatekeeper acceptance before publishing. Local ad-hoc previews
remain available only through the explicit testing-preview path.

## Complete the Apple account setup

1. [Enroll in the Apple Developer Program](https://developer.apple.com/programs/enroll/).
   Complete enrollment, agreements, payment and identity verification yourself.
2. Once membership is active, use Xcode → Settings → Accounts → your enrolled
   team → Manage Certificates to create **Developer ID Application** and
   **Developer ID Installer** identities. Apple also provides a
   [certificate creation guide](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/).
   Both identities and their private keys must be installed in this Mac's login
   Keychain. Use the same enrolled team for every release; an Apple Development
   certificate does not replace Developer ID.
3. Copy `scripts/release.env.example` to `.release.env` in the repository root.
   Enter the enrolled Team ID and the exact certificate names from Keychain
   Access → My Certificates. This file is ignored by Git. Store no passwords
   or private keys in it.
4. Create the notarization profile interactively in Terminal:

   ```sh
   xcrun notarytool store-credentials MacPlazaNotary
   ```

   Enter your Apple account, enrolled Team ID and an app-specific password
   when Apple's tool prompts. Credentials are saved in Keychain. Do not paste
   them into chat, a script or a command-line argument. Apple's
   [notarization guide](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
   also describes App Store Connect API-key authentication if preferred.

## Build and verify

```sh
zsh scripts/build-signed-release.sh --check
zsh scripts/build-signed-release.sh
```

The check validates Application and Installer identities against the configured
team and tests the Keychain notarization profile. It makes no certificates and
never exports private keys. Missing credentials stop the build before artifacts
are modified; signing does not fall back to ad-hoc mode.

The build signs nested code from the inside out with Hardened Runtime and secure
timestamps, preserves Sparkle helper entitlements and removes debugging access.
It notarizes/staples the app, packages the stapled app for Sparkle, signs the PKG,
notarizes/staples the DMG and regenerates its checksum. The output app is separate
from the open development app at `Artifacts/Developer-ID/Mac Plaza.app`.
Apple submission IDs and results are kept in ignored `Artifacts/Notarization`.
The private `.plazapack` is not added to the release.

Before a public release, increment version/build and test the signed app's
Discord connection, original Mii renderer, music and actual old-to-new Sparkle
update on a test Mac. Repeat a second signed update to confirm Keychain access
persists. The first transition from an ad-hoc preview may request **Always
Allow** once for each saved sign-in item. Developer ID prevents changing code
hashes from becoming the app's identity on each later update; it cannot guarantee
that unrelated Keychain locking/password issues never prompt.

Keep `local.macplaza.app`, the enrolled Team ID and the existing Sparkle EdDSA
public key constant. A stable Developer ID designated requirement is checked
after signing; no custom code-hash requirement or broadened Keychain ACL is used.
The `macplaza-updates` Sparkle signing key remains in Keychain and continues to
sign update archives independently of the Apple signing certificate.

`publish-release.sh` now verifies Developer ID/notarization on the actual app ZIP
and installer artifacts before staging or uploading. Publishing remains a
separate authorized step. Existing published previews and the active feed are
unchanged. Local development builds without a configured signing identity may
still use the existing ad-hoc path in `build-app.sh`.
