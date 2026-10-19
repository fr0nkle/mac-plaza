"""Sign the tested Windows installer metadata using the existing Sparkle Keychain key."""
import base64
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile

installer, signer, output = map(Path, sys.argv[1:4])
version = installer.name.removeprefix('Plaza-Windows-').removesuffix('-Setup-x64.exe')
payload = json.dumps(dict(schema=1, platform='win32', arch='x64', version=version,
    url=f'https://github.com/fr0nkle/mac-plaza/releases/download/windows-v{version}/{installer.name}',
    size=installer.stat().st_size, sha256=hashlib.sha256(installer.read_bytes()).hexdigest(),
    notes=(Path(__file__).resolve().parents[1] / 'RELEASE-NOTES.md').read_text()), separators=(',', ':')).encode()
with tempfile.TemporaryDirectory(prefix='plaza-update-sign-') as folder:
    source = Path(folder) / 'manifest.json'
    source.write_bytes(payload)
    signature = subprocess.check_output([str(signer), '--account', 'macplaza-updates', '-p', str(source)], text=True).strip()
output.write_text(json.dumps(dict(payload=base64.b64encode(payload).decode(), signature=signature), indent=2) + '\n')
print('Signed Windows update metadata:', version)
