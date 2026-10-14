"""Developer ID signing; local unsigned previews use build-app.sh's ad-hoc path."""
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile

from release_signing import SigningError, find_identity, verify_app

MACHO = {bytes.fromhex(value) for value in (
    "feedface", "cefaedfe", "feedfacf", "cffaedfe",
    "cafebabe", "bebafeca", "cafebabf", "bfbafeca")}


def targets(app):
    for path in sorted(app.rglob("*"), key=lambda p: len(p.parts), reverse=True):
        if path.is_symlink():
            continue
        if path.is_file():
            with path.open("rb") as stream:
                if stream.read(4) in MACHO:
                    yield path
        elif path.suffix in (".app", ".xpc", ".framework"):
            yield path
    yield app


def release_entitlements(path):
    # Keep Sparkle helper sandbox entitlements, removing development debugging.
    result = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(path)], capture_output=True)
    if not result.stdout.strip():
        if result.returncode and b"not signed at all" not in result.stderr:
            raise SigningError("Could not inspect existing entitlements: " + str(path))
        return {}
    entitlements = plistlib.loads(result.stdout)
    entitlements.pop("com.apple.security.get-task-allow", None)
    return entitlements


def sign_app(app, requested, team):
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != "local.macplaza.app":
        raise SigningError("Keep Mac Plaza's bundle identifier local.macplaza.app across updates.")
    identity = find_identity(requested, "Application", team)
    with tempfile.TemporaryDirectory(prefix="macplaza-sign-") as temporary:
        entitlement_file = Path(temporary) / "entitlements.plist"
        for path in targets(app):
            entitlements = release_entitlements(path)
            command = ["codesign", "--force", "--sign", identity, "--options", "runtime",
                       "--timestamp", "--preserve-metadata=identifier"]
            if entitlements:
                entitlement_file.write_bytes(plistlib.dumps(entitlements))
                command += ["--entitlements", str(entitlement_file)]
            subprocess.run(command + [str(path)], check=True)
    verify_app(app, team)


if __name__ == "__main__":
    try:
        if len(sys.argv) != 3:
            raise SigningError("Usage: sign-app.py APP 'Developer ID Application: NAME (TEAMID)'")
        sign_app(Path(sys.argv[1]).resolve(), sys.argv[2], os.environ.get("PLAZA_TEAM_ID", ""))
    except (SigningError, subprocess.CalledProcessError) as error:
        sys.exit(str(error))
