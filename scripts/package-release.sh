#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' scripts/Info.plist)
app="$PWD/Artifacts/Mac Plaza.app"
codesign --verify --deep --strict "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "Artifacts/Mac-Plaza-$version.zip"
staging=$(mktemp -d /tmp/macplaza-source.XXXXXX)
trap 'rm -rf "$staging"' EXIT
sourceName="Mac-Plaza-$version-Source"
mkdir "$staging/$sourceName"
for item in Sources Tests scripts ThirdParty Package.swift README.md DISTRIBUTION.md LOCAL_FEATURES.md ORIGINAL_CROWD_PORT.md .gitignore; do
  ditto "$item" "$staging/$sourceName/$item"
done
mkdir "$staging/$sourceName/Server"
# Explicit allowlist: never package environment secrets, databases, or virtual environments.
for item in server.py updates.py downloads.py presence_bot.py run_local.py friend_test.py login_start.py 'Start Friend Test.command' 'Stop Friend Test.command' 'Enable Hosting at Login.command' 'Disable Hosting at Login.command' test_server.py test_presence_bot.py test_updates.py test_downloads.py requirements.txt README.md .env.example; do
  ditto "Server/$item" "$staging/$sourceName/Server/$item"
done
ditto -c -k --sequesterRsrc --keepParent "$staging/$sourceName" "Artifacts/$sourceName.zip"
(cd Artifacts; shasum -a 256 "Mac-Plaza-$version.zip" > "Mac-Plaza-$version.sha256"; shasum -a 256 "$sourceName.zip" > "$sourceName.sha256")
unzip -t "Artifacts/Mac-Plaza-$version.zip" | tail -n 1
unzip -t "Artifacts/$sourceName.zip" | tail -n 1
