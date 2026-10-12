"""Sign a built update and atomically stage it for the local private beta service."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
info = plistlib.loads((root / 'scripts/Info.plist').read_bytes())
version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
archive = root / 'Artifacts' / ('Mac-Plaza-' + version + '.zip')
source = root / 'Artifacts' / ('Mac-Plaza-' + version + '-Source.zip')
signature = subprocess.check_output([str(root / 'ThirdParty/Sparkle/bin/sign_update'), '--account', 'macplaza-updates', '-p', str(archive)], text=True).strip()
notes = Path(sys.argv[1]).read_text() if len(sys.argv) > 1 else 'Mac Plaza private testing release.'
manifest = dict(version=version, build=build, archive=archive.name, source=source.name,
                signature=signature, length=archive.stat().st_size, notes=notes,
                sha256=hashlib.sha256(archive.read_bytes()).hexdigest(),
                sourceSHA256=hashlib.sha256(source.read_bytes()).hexdigest())
destination = root / 'Server/.updates'; destination.mkdir(mode=0o700, exist_ok=True)
for asset in (archive, source):
    temporary = destination / (asset.name + '.tmp')
    shutil.copyfile(asset, temporary); os.chmod(temporary, 0o600)
    temporary.replace(destination / asset.name)
output = root / 'Artifacts/release.json'
output.write_text(json.dumps(manifest, indent=2) + '\n')
temporary = destination / 'release.json.tmp'; temporary.write_bytes(output.read_bytes())
temporary.replace(destination / 'release.json')
print('Signed and staged private testing update:', version, 'build', build)
