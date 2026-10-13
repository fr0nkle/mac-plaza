#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
gh="${PLAZA_GH:-$PWD/Server/.tools/gh}"
[[ -x "$gh" ]] || gh=gh
repo=fr0nkle/mac-plaza
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' scripts/Info.plist)
notes="scripts/release-notes/$version.md"
python3 scripts/prepare-update.py "$notes"
python3 scripts/update-download-page.py
$gh release create "v$version" --repo "$repo" --prerelease --title "Mac Plaza $version — testing preview" \
  --notes-file "$notes" \
  "Artifacts/Mac-Plaza-$version.zip" "Artifacts/Mac-Plaza-$version-Source.zip" \
  "Artifacts/Mac-Plaza-$version.dmg" "Artifacts/Mac-Plaza-$version.pkg" \
  "Artifacts/Mac-Plaza-$version.sha256" "Artifacts/Mac-Plaza-$version.dmg.sha256" Artifacts/release.json
python3 scripts/stage-public-release.py
