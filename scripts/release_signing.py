"""Shared Developer ID checks. Never exports keys or changes Keychain access."""
import os
import plistlib
import re
import subprocess


class SigningError(RuntimeError):
    pass


def validate_team(team):
    if not re.fullmatch(r"[A-Z0-9]{10}", team) or team == "YOURTEAMID":
        raise SigningError("Set PLAZA_TEAM_ID to your enrolled Apple Developer team's 10-character ID. See scripts/DEVELOPER-ID.md.")


def select_identity(output, requested, kind, team):
    validate_team(team)
    identities = re.findall(r'\)\s+([A-Fa-f0-9]{40})\s+"([^"\n]+)"', output)
    matches = [(digest, name) for digest, name in identities
               if requested in (digest, name) or requested.upper() == digest.upper()]
    if len(matches) != 1:
        raise SigningError("Install exactly one matching Developer ID " + kind + " identity with its private key. See scripts/DEVELOPER-ID.md.")
    digest, name = matches[0]
    if not name.startswith("Developer ID " + kind + ": ") or not name.endswith("(" + team + ")"):
        raise SigningError("Use a Developer ID " + kind + " certificate from the configured team; Apple Development certificates are not distribution identities.")
    return digest


def find_identity(requested, kind, team):
    validate_team(team)
    policy = "codesigning" if kind == "Application" else "basic"
    output = subprocess.check_output(["security", "find-identity", "-v", "-p", policy], text=True)
    return select_identity(output, requested, kind, team)


def check_metadata(metadata, requirement, team):
    validate_team(team)
    fields = dict(line.split("=", 1) for line in metadata.splitlines() if "=" in line)
    authorities = [line for line in metadata.splitlines() if line.startswith("Authority=")]
    hardened = any(line.startswith("CodeDirectory ") and re.search(r"flags=0x[0-9a-fA-F]+\([^)]*\bruntime\b", line)
                   for line in metadata.splitlines())
    if (fields.get("Identifier") != "local.macplaza.app" or fields.get("TeamIdentifier") != team
            or not any(line.startswith("Authority=Developer ID Application: ") for line in authorities)
            or not hardened or not fields.get("Timestamp")):
        raise SigningError("The app must have a timestamped Developer ID signature, Hardened Runtime and the configured team/bundle identity.")
    if "adhoc" in metadata or "designated => cdhash" in requirement:
        raise SigningError("Ad-hoc signatures change identity between builds and cannot be published as Developer ID releases.")
    if ('identifier "local.macplaza.app"' not in requirement or "anchor apple generic" not in requirement
            or 'certificate leaf[subject.OU] = "' + team + '"' not in requirement):
        raise SigningError("The app's designated requirement must retain its bundle identifier and developer team across updates.")


def verify_app(app, team, notarized=False):
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    result = subprocess.run(["codesign", "-d", "--verbose=4", str(app)], capture_output=True, text=True, check=True)
    requirement = subprocess.run(["codesign", "-d", "-r-", str(app)], capture_output=True, text=True, check=True)
    check_metadata(result.stdout + result.stderr, requirement.stdout + requirement.stderr, team)
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != "local.macplaza.app":
        raise SigningError("The app's bundle identifier changed.")
    entitlements = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(app)], capture_output=True, check=True).stdout
    if entitlements.strip() and plistlib.loads(entitlements).get("com.apple.security.get-task-allow"):
        raise SigningError("Release apps must not allow debugger attachment.")
    if notarized:
        subprocess.run(["xcrun", "stapler", "validate", str(app)], check=True)
        subprocess.run(["spctl", "--assess", "--type", "execute", str(app)], check=True)
    return info


def preflight():
    team = os.environ.get("PLAZA_TEAM_ID", "")
    validate_team(team)
    application = find_identity(os.environ.get("PLAZA_SIGN_IDENTITY", ""), "Application", team)
    installer = find_identity(os.environ.get("PLAZA_INSTALLER_IDENTITY", ""), "Installer", team)
    profile = os.environ.get("PLAZA_NOTARY_PROFILE", "MacPlazaNotary")
    subprocess.run(["xcrun", "notarytool", "history", "--keychain-profile", profile, "--output-format", "json"],
                   check=True, stdout=subprocess.DEVNULL)
    return application, installer


if __name__ == "__main__":
    try:
        preflight()
        print("Developer ID Application, Installer and notarization credentials are ready.")
    except (SigningError, subprocess.CalledProcessError) as error:
        raise SystemExit(str(error))
