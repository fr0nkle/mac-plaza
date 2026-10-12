#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' scripts/Info.plist)
app="$PWD/Artifacts/Mac Plaza.app"
staging=$(mktemp -d /tmp/macplaza-installer.XXXXXX)
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/root/Applications" "$staging/image"
ditto "$app" "$staging/root/Applications/Mac Plaza.app"
pkgbuild --root "$staging/root" --identifier org.squidproductions.macplaza.installer \
  --version "$version" --install-location / --component-plist scripts/installer-component.plist "$staging/component.pkg"
productbuild --distribution scripts/installer-distribution.xml --package-path "$staging" "$staging/Mac-Plaza-$version.pkg"
if [[ -n "${PLAZA_INSTALLER_IDENTITY:-}" ]]; then
  productsign --sign "$PLAZA_INSTALLER_IDENTITY" "$staging/Mac-Plaza-$version.pkg" "Artifacts/Mac-Plaza-$version.pkg"
else
  cp "$staging/Mac-Plaza-$version.pkg" "Artifacts/Mac-Plaza-$version.pkg"
fi
cp "Artifacts/Mac-Plaza-$version.pkg" "$staging/image/Install Mac Plaza.pkg"
ditto "$app" "$staging/image/Mac Plaza.app"
ln -s /Applications "$staging/image/Applications"
cp "Artifacts/Mac-Plaza-$version-Source.zip" "$staging/image/Corresponding Source.zip"
cp scripts/TESTING-README.txt "$staging/image/START HERE.txt"
hdiutil create -volname "Mac Plaza $version" -srcfolder "$staging/image" -ov -format UDZO "Artifacts/Mac-Plaza-$version.dmg"
shasum -a 256 "Artifacts/Mac-Plaza-$version.dmg" > "Artifacts/Mac-Plaza-$version.dmg.sha256"
echo "Installer: Artifacts/Mac-Plaza-$version.dmg"
