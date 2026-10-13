"""Explicitly publish only an installer and its matching source for the website."""
import json
from pathlib import Path
import re
from downloads import DownloadStore


def stage(root, installer, source, version, build):
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+)*", version) or not str(build).isdigit():
        raise ValueError("Invalid release version")
    store = DownloadStore(root)
    release = dict(version=version, build=str(build), files={})
    for key, file in (("installer", installer), ("source", source)):
        token, data = store.create(file, days=None)
        release["files"][key] = dict(token=token, filename=data["filename"],
                                     size=data["size"], sha256=data["sha256"])
    temporary = Path(root) / "public-release.tmp"
    temporary.write_text(json.dumps(release, indent=2) + "\n")
    temporary.chmod(0o600)
    temporary.replace(Path(root) / "public-release.json")


def current(root):
    data = json.loads((Path(root) / "public-release.json").read_text())
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+)*", data["version"]):
        raise ValueError("Invalid version")
    store = DownloadStore(root)
    for key in ("installer", "source"):
        _, asset = store.resolve(data["files"][key]["token"])
        for field in ("filename", "size", "sha256"):
            if data["files"][key][field] != asset[field]:
                raise ValueError("Release does not match registered asset")
    return data
