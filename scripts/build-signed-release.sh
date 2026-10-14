#!/bin/zsh
# Build and notarize locally; publishing to GitHub remains a separate action.
set -euo pipefail
cd "${0:A:h:h}"
source scripts/release-config.zsh
python3 scripts/release_signing.py
if [[ "${1:-}" == --check ]]; then
  exit 0
fi
if [[ $# != 0 ]]; then
  print -u2 'Usage: zsh scripts/build-signed-release.sh [--check]'
  exit 2
fi
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' scripts/Info.plist)
# A separate app prevents replacing an open development build or its resources.
export PLAZA_APP_PATH="${PLAZA_APP_PATH:-$PWD/Artifacts/Developer-ID/Mac Plaza.app}"
export PLAZA_DISTRIBUTION=1
profile="${PLAZA_NOTARY_PROFILE:-MacPlazaNotary}"
notarydir="$PWD/Artifacts/Notarization/$version"
mkdir -p "$notarydir"
zsh scripts/build-app.sh
ditto -c -k --sequesterRsrc --keepParent "$PLAZA_APP_PATH" "$notarydir/submission.zip"
function notarize() {
  xcrun notarytool submit "$1" --keychain-profile "$profile" --wait --output-format json > "$2"
  python3 - "$2" <<'PY'
import json,sys
result=json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted':
    raise SystemExit('Apple did not accept notarization. Inspect '+sys.argv[1]+' and request the notarytool log for its submission ID.')
print('Apple accepted notarization:',result['id'])
PY
}
notarize "$notarydir/submission.zip" "$notarydir/app.json"
xcrun stapler staple "$PLAZA_APP_PATH"
# The update archive must contain the stapled app, not the submission ZIP.
zsh scripts/package-release.sh
zsh scripts/build-installer.sh
codesign --force --sign "$PLAZA_SIGN_IDENTITY" --timestamp "Artifacts/Mac-Plaza-$version.dmg"
notarize "Artifacts/Mac-Plaza-$version.dmg" "$notarydir/installer.json"
xcrun stapler staple "Artifacts/Mac-Plaza-$version.dmg"
# The PKG is also distributed separately from the DMG.
xcrun stapler staple "Artifacts/Mac-Plaza-$version.pkg"
shasum -a 256 "Artifacts/Mac-Plaza-$version.dmg" > "Artifacts/Mac-Plaza-$version.dmg.sha256"
python3 scripts/verify-release-signing.py
print 'Signed, notarized release is ready. Publishing is a separate step.'
