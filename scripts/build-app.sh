#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
source scripts/release-config.zsh
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
swift build -c release --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security
swift scripts/make-icon.swift Artifacts/PlazaIcon.iconset
iconutil -c icns Artifacts/PlazaIcon.iconset -o Artifacts/PlazaIcon.icns
app="${PLAZA_APP_PATH:-$PWD/Artifacts/Mac Plaza.app}"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/MacPlaza "$app/Contents/MacOS/MacPlaza"
cp scripts/Info.plist "$app/Contents/Info.plist"
if [[ -n "${PLAZA_DISCORD_APPLICATION_ID:-}" ]]; then
  [[ "$PLAZA_DISCORD_APPLICATION_ID" == <-> ]] || { echo "PLAZA_DISCORD_APPLICATION_ID must be numeric." >&2; exit 1; }
  /usr/libexec/PlistBuddy -c "Set :PlazaDiscordApplicationID $PLAZA_DISCORD_APPLICATION_ID" "$app/Contents/Info.plist"
fi
ditto .build/release/MacPlaza_MacPlaza.bundle/FFL "$app/Contents/Resources/FFL"
ditto .build/release/MacPlaza_MacPlaza.bundle/Audio "$app/Contents/Resources/Audio"
if [[ "${PLAZA_DISTRIBUTION:-0}" == 1 ]]; then
  # A private friend release may explicitly include the user-requested Miiverse track.
  python3 - "$app/Contents/Resources/Audio" "${PLAZA_INCLUDE_MIIVERSE_MUSIC:-0}" <<'PY'
from pathlib import Path
import sys
directory = Path(sys.argv[1])
included = {'miiverse.m4a'} if sys.argv[2] == '1' else set()
if included and not (directory / 'miiverse.m4a').is_file():
    raise SystemExit('The requested bundled Miiverse music is missing.')
ui_sounds = directory / "UI"
if ui_sounds.exists():
    import shutil
    shutil.rmtree(ui_sounds)
for item in directory.iterdir():
    if item.suffix.lower() in ('.m4a', '.wav') and item.name not in included:
        item.unlink()
PY
fi
mkdir -p "$app/Contents/Frameworks"
ditto ThirdParty/DiscordSocialSDK/discord_social_sdk/lib/release/discord_partner_sdk.framework "$app/Contents/Frameworks/discord_partner_sdk.framework"
ditto ThirdParty/Sparkle/Sparkle.framework "$app/Contents/Frameworks/Sparkle.framework"
cp ThirdParty/Sparkle/LICENSE "$app/Contents/Resources/Sparkle-LICENSE.txt"
cp ThirdParty/DiscordSocialSDK/discord_social_sdk/License-Notices.txt "$app/Contents/Resources/Discord-License-Notices.txt"
cp LICENSE "$app/Contents/Resources/Mac-Plaza-LICENSE.txt"
cp LICENSING.md "$app/Contents/Resources/Mac-Plaza-Licensing.md"
if [[ -f Artifacts/PlazaIcon.icns ]]; then
  cp Artifacts/PlazaIcon.icns "$app/Contents/Resources/PlazaIcon.icns"
fi
if [[ -n "${PLAZA_SIGN_IDENTITY:-}" ]]; then
  python3 scripts/sign-app.py "$app" "$PLAZA_SIGN_IDENTITY"
else
  codesign --force --deep --sign - "$app"
fi
echo "Built: $app"
