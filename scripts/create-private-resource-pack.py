#!/usr/bin/env python3
"""Package locally supplied renderer assets and recordings; never downloads media.

Output belongs in ignored Artifacts/Private, separate from public app releases.
The file contains no saved characters, notes, account data or executable code.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import struct
import tempfile


def create(root, output):
    sources = [
        ("faces", "FFLResHigh.dat", None, "Wii U faces", root / "Local Resources/Wii U FFL/FFLResHigh.dat"),
        ("bodies", "plaza-body.json", None, "Wii U bodies and animations", root / "Local Resources/Wii U Menu/plaza-body.json"),
    ]
    for role, title in [
        ("warawara-home", "Wii U Home Menu · Extended"),
        ("mii-maker", "Mii Maker · Wii U"),
        ("friends-menu", "Friend List · Wii U"),
        ("system-settings", "System Settings · Wii U"),
        ("note-writing", "Writing Notes · Wii U Chat"),
        ("miiverse", "Miiverse · Wii U"),
    ]:
        name = role + ".m4a"
        sources.append(("music", name, role, title, root / "Sources/MacPlaza/Resources/Audio" / name))
    entries = []
    for kind, name, role, title, source in sources:
        digest = hashlib.sha256()
        with source.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        entry = dict(kind=kind, file=name, name=title, size=source.stat().st_size, sha256=digest.hexdigest())
        if role:
            entry["role"] = role
        entries.append(entry)
    manifest = json.dumps(dict(version=1, name="Wii U Plaza Resources", entries=entries), ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    total = 12 + len(manifest) + sum(entry["size"] for entry in entries)
    if len(manifest) > 65536 or total > 512 * 1024 * 1024:
        raise ValueError("Resource pack exceeds importer limits")
    output.parent.mkdir(parents=True, exist_ok=True)
    handle, temporary = tempfile.mkstemp(prefix=".plazapack-", dir=output.parent)
    try:
        with os.fdopen(handle, "wb") as stream:
            stream.write(b"PLAZAPK1" + struct.pack("<I", len(manifest)) + manifest)
            for entry, source in zip(entries, sources):
                digest = hashlib.sha256()
                size = 0
                with source[4].open("rb") as payload:
                    for chunk in iter(lambda: payload.read(1024 * 1024), b""):
                        stream.write(chunk)
                        digest.update(chunk)
                        size += len(chunk)
                if size != entry["size"] or digest.hexdigest() != entry["sha256"]:
                    raise ValueError("A source changed while packaging; try again")
        os.replace(temporary, output)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    print(f"Created {output} ({total:,} bytes; original renderer and six music tracks)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    args = parser.parse_args()
    if args.output.suffix.lower() != ".plazapack":
        parser.error("output must end in .plazapack")
    create(args.root, args.output.resolve())
