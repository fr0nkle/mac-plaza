"""Check the actual update archive and installers before signing/publishing a feed."""
import os
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import zipfile

from release_signing import SigningError, validate_team, verify_app


def verify_release(root, testing_preview=False):
    team = os.environ.get("PLAZA_TEAM_ID", "")
    if not testing_preview:
        validate_team(team)
    expected = plistlib.loads((root / "scripts/Info.plist").read_bytes())
    version = expected["CFBundleShortVersionString"]
    archive = root / "Artifacts" / ("Mac-Plaza-" + version + ".zip")
    with zipfile.ZipFile(archive) as source:
        for name in source.namelist():
            if name.startswith("/") or ".." in Path(name).parts:
                raise SigningError("Unexpected path in the update archive.")
    with tempfile.TemporaryDirectory(prefix="macplaza-release-check-") as directory:
        subprocess.run(["ditto", "-x", "-k", str(archive), directory], check=True)
        app = Path(directory) / "Mac Plaza.app"
        if testing_preview:
            subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
            result = subprocess.run(["codesign", "-d", "--verbose=4", str(app)], capture_output=True, text=True, check=True)
            if "Signature=adhoc" not in result.stderr + result.stdout:
                raise SigningError("The testing-preview path requires an explicitly ad-hoc signed app.")
            actual = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        else:
            actual = verify_app(app, team, notarized=True)
        for key in ("CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion", "SUPublicEDKey", "PlazaDiscordApplicationID"):
            if actual.get(key) != expected.get(key):
                raise SigningError("The archived app does not match release metadata: " + key)
        if actual.get("CFBundleIdentifier") != "local.macplaza.app":
            raise SigningError("The app's bundle identifier changed.")
    if testing_preview:
        pkg = root / "Artifacts" / ("Mac-Plaza-" + version + ".pkg")
        if not pkg.is_file() or pkg.stat().st_size == 0:
            raise SigningError("The testing installer is missing.")
        dmg = root / "Artifacts" / ("Mac-Plaza-" + version + ".dmg")
        subprocess.run(["hdiutil", "verify", str(dmg)], check=True, stdout=subprocess.DEVNULL)
        print("Verified ad-hoc testing preview (not Apple signed or notarized):", version)
        return
    pkg = root / "Artifacts" / ("Mac-Plaza-" + version + ".pkg")
    result = subprocess.run(["pkgutil", "--check-signature", str(pkg)], capture_output=True, text=True, check=True)
    if "Developer ID Installer: " not in result.stdout or "(" + team + ")" not in result.stdout:
        raise SigningError("The installer must use a Developer ID Installer certificate from the same team.")
    subprocess.run(["xcrun", "stapler", "validate", str(pkg)], check=True)
    subprocess.run(["spctl", "--assess", "--type", "install", str(pkg)], check=True)
    dmg = root / "Artifacts" / ("Mac-Plaza-" + version + ".dmg")
    subprocess.run(["xcrun", "stapler", "validate", str(dmg)], check=True)
    print("Verified Developer ID and notarization for app ZIP, installer and DMG:", version)


if __name__ == "__main__":
    try:
        if sys.argv[1:] not in ([], ["--testing-preview"]):
            sys.exit("Usage: verify-release-signing.py [--testing-preview]")
        verify_release(Path(__file__).resolve().parent.parent, testing_preview=sys.argv[1:] == ["--testing-preview"])
    except (SigningError, subprocess.CalledProcessError, OSError) as error:
        sys.exit(str(error))
