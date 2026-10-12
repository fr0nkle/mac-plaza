#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
swift build -c release --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security
swift scripts/make-icon.swift Artifacts/PlazaIcon.iconset
iconutil -c icns Artifacts/PlazaIcon.iconset -o Artifacts/PlazaIcon.icns
app="$PWD/Artifacts/Mac Plaza.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/MacPlaza "$app/Contents/MacOS/MacPlaza"
cp scripts/Info.plist "$app/Contents/Info.plist"
ditto .build/release/MacPlaza_MacPlaza.bundle/FFL "$app/Contents/Resources/FFL"
ditto .build/release/MacPlaza_MacPlaza.bundle/Audio "$app/Contents/Resources/Audio"
mkdir -p "$app/Contents/Frameworks"
ditto ThirdParty/DiscordSocialSDK/discord_social_sdk/lib/release/discord_partner_sdk.framework "$app/Contents/Frameworks/discord_partner_sdk.framework"
ditto ThirdParty/Sparkle/Sparkle.framework "$app/Contents/Frameworks/Sparkle.framework"
cp ThirdParty/Sparkle/LICENSE "$app/Contents/Resources/Sparkle-LICENSE.txt"
cp ThirdParty/DiscordSocialSDK/discord_social_sdk/License-Notices.txt "$app/Contents/Resources/Discord-License-Notices.txt"
if [[ -f Artifacts/PlazaIcon.icns ]]; then
  cp Artifacts/PlazaIcon.icns "$app/Contents/Resources/PlazaIcon.icns"
fi
if [[ -n "${PLAZA_SIGN_IDENTITY:-}" ]]; then
  python3 scripts/sign-app.py "$app" "$PLAZA_SIGN_IDENTITY"
else
  codesign --force --deep --sign - "$app"
fi
echo "Built: $app"
