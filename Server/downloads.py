"""Expiring, revocable ZIP links. Only a token hash is stored in the link registry."""
import hashlib
import json
import math
import os
from pathlib import Path
import re
import secrets
import shutil
import time


class DownloadStore:
    def __init__(self, root, now=time.time):
        self.root = Path(root).resolve()
        self.now = now

    def key(self, token):
        if not isinstance(token, str) or not re.fullmatch(r"[A-Za-z0-9_-]{43}", token):
            raise FileNotFoundError("Download unavailable.")
        return hashlib.sha256(token.encode()).hexdigest()

    def create(self, source, days=7):
        source = Path(source)
        if source.suffix.lower() != ".zip" or not source.is_file() or not 1 <= days <= 30:
            raise ValueError("Choose an existing ZIP and an expiry between 1 and 30 days.")
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9 ._()-]{0,159}\.zip", source.name):
            raise ValueError("Use a simple ZIP filename.")
        self.root.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.root.chmod(0o700)
        token = secrets.token_urlsafe(32)
        asset = self.root / (secrets.token_hex(16) + ".zip")
        shutil.copyfile(source, asset)
        asset.chmod(0o600)
        sha = hashlib.sha256()
        with asset.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                sha.update(chunk)
        metadata = dict(asset=asset.name, filename=source.name, size=asset.stat().st_size,
                        expires=self.now() + days * 86400, sha256=sha.hexdigest())
        record = self.root / (self.key(token) + ".json")
        with record.open("x") as stream:
            json.dump(metadata, stream)
        record.chmod(0o600)
        return token, metadata

    def resolve(self, token):
        record = self.root / (self.key(token) + ".json")
        try:
            data = json.loads(record.read_text())
            if not isinstance(data["expires"], (int, float)) or not math.isfinite(data["expires"]) or data["expires"] <= self.now():
                raise ValueError("Expired")
            if not re.fullmatch(r"[0-9a-f]{32}\.zip", data["asset"]):
                raise ValueError("Invalid asset")
            if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9 ._()-]{0,159}\.zip", data["filename"]):
                raise ValueError("Invalid filename")
            if not re.fullmatch(r"[0-9a-f]{64}", data["sha256"]):
                raise ValueError("Invalid checksum")
            asset = (self.root / data["asset"]).resolve()
            if asset.parent != self.root or not asset.is_file() or asset.stat().st_size != data["size"]:
                raise ValueError("Unavailable asset")
            return asset, data
        except (OSError, ValueError, KeyError, TypeError):
            raise FileNotFoundError("Download unavailable.") from None

    def revoke(self, token):
        # Removing the record revokes this link; the ZIP stays for local recovery.
        (self.root / (self.key(token) + ".json")).unlink(missing_ok=True)


def byte_range(value, size):
    """One resumable byte range; reject unsupported/multiple ranges with 416."""
    if not value:
        return 0, size - 1
    match = re.fullmatch(r"bytes=([0-9]{0,20})-([0-9]{0,20})", value)
    if not match or not any(match.groups()) or size == 0:
        raise ValueError("Unsatisfiable range")
    first, last = match.groups()
    if not first:
        suffix = int(last)
        if suffix == 0:
            raise ValueError("Unsatisfiable range")
        return max(0, size - suffix), size - 1
    first = int(first)
    last = min(int(last), size - 1) if last else size - 1
    if first >= size or last < first:
        raise ValueError("Unsatisfiable range")
    return first, last
