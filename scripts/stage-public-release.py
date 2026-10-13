"""Publish a built installer and corresponding source to the download page."""
import json
import os
import hashlib
from pathlib import Path
import sys

root = Path(__file__).resolve().parent.parent
runtime = root
marker = root / "Server/.run/hosting-runtime.json"
if marker.exists():
    runtime = Path(json.loads(marker.read_text())["root"])
sys.path.insert(0, str(root / "Server"))
from public_releases import stage

os.umask(0o077)
manifest = json.loads((root / "Artifacts/release.json").read_text())
version = manifest["version"]
installer = root / "Artifacts" / ("Mac-Plaza-" + version + ".dmg")
assert hashlib.sha256(installer.read_bytes()).hexdigest() == manifest["installerSHA256"], "Installer checksum mismatch"
stage(runtime / "Server/.downloads", installer,
      root / "Artifacts" / manifest["source"], version, manifest["build"])
print("Download page now serves Mac Plaza " + version + ".")
