#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
source scripts/release-config.zsh
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' scripts/Info.plist)
app="${PLAZA_APP_PATH:-$PWD/Artifacts/Mac Plaza.app}"
staging=$(mktemp -d /tmp/macplaza-installer.XXXXXX)
trap 'rm -rf "$staging"' EXIT
mkdir -p "$staging/root/Applications" "$staging/image"
ditto "$app" "$staging/root/Applications/Mac Plaza.app"
pkgbuild --root "$staging/root" --identifier org.squidproductions.macplaza.installer \
  --version "$version" --install-location / --component-plist scripts/installer-component.plist "$staging/component.pkg"
productbuild --distribution scripts/installer-distribution.xml --package-path "$staging" "$staging/Mac-Plaza-$version.pkg"
if [[ -n "${PLAZA_INSTALLER_IDENTITY:-}" ]]; then
  productsign --timestamp --sign "$PLAZA_INSTALLER_IDENTITY" "$staging/Mac-Plaza-$version.pkg" "Artifacts/Mac-Plaza-$version.pkg"
else
  cp "$staging/Mac-Plaza-$version.pkg" "Artifacts/Mac-Plaza-$version.pkg"
fi
cp "Artifacts/Mac-Plaza-$version.pkg" "$staging/image/Install Mac Plaza.pkg"
ditto "$app" "$staging/image/Mac Plaza.app"
ln -s /Applications "$staging/image/Applications"
# Source archives contain developer build tools that are not app runtime code.
# Offer corresponding source alongside the binary release, with equivalent access.
python3 - "$version" "Artifacts/Mac-Plaza-$version-Source.zip" "$staging/image/Corresponding Source.txt" <<'PY_SOURCE'
from pathlib import Path
import hashlib,sys
version,source,output=sys.argv[1:]
asset=Path(source)
url='https://github.com/fr0nkle/mac-plaza/releases/download/v'+version+'/'+asset.name
Path(output).write_text('Mac Plaza corresponding source\n\n'+url+'\n\nSHA-256: '+hashlib.sha256(asset.read_bytes()).hexdigest()+'\n\nThe source is available without a GitHub account, alongside this installer.\nIt includes original Mac Plaza code and component notices.\n')
PY_SOURCE
cp scripts/TESTING-README.txt "$staging/image/START HERE.txt"
hdiutil create -volname "Mac Plaza $version" -srcfolder "$staging/image" -ov -format UDZO "Artifacts/Mac-Plaza-$version.dmg"
shasum -a 256 "Artifacts/Mac-Plaza-$version.dmg" > "Artifacts/Mac-Plaza-$version.dmg.sha256"
shasum -a 256 "Artifacts/Mac-Plaza-$version.pkg" > "Artifacts/Mac-Plaza-$version.pkg.sha256"
echo "Installer: Artifacts/Mac-Plaza-$version.dmg"
