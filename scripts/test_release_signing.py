import importlib.util
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from release_signing import SigningError, check_metadata, select_identity

spec = importlib.util.spec_from_file_location("sign_app", Path(__file__).with_name("sign-app.py"))
sign_app = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sign_app)
spec = importlib.util.spec_from_file_location("verify_release", Path(__file__).with_name("verify-release-signing.py"))
verify_release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verify_release)
TEAM = "A123456789"
HASH = "A" * 40
NAME = "Developer ID Application: Example (" + TEAM + ")"
IDENTITIES = '  1) ' + HASH + ' "' + NAME + '"\n  1 valid identities found\n'
METADATA = '''Identifier=local.macplaza.app
CodeDirectory v=20500 size=100 flags=0x10000(runtime) hashes=1+7 location=embedded
Authority=Developer ID Application: Example (A123456789)
Authority=Developer ID Certification Authority
Authority=Apple Root CA
TeamIdentifier=A123456789
Timestamp=Oct 14, 2026 at 12:00:00
CDHash=0123456789
'''
REQUIREMENT = 'designated => identifier "local.macplaza.app" and anchor apple generic and certificate leaf[subject.OU] = "A123456789"'


class SigningTests(unittest.TestCase):
    def test_default_release_never_accepts_unconfigured_preview(self):
        with patch.dict(os.environ, {"PLAZA_TEAM_ID": ""}), self.assertRaises(SigningError):
            verify_release.verify_release(Path("/nonexistent/plaza-release"))

    def test_preview_opt_in_still_rejects_changed_update_identity(self):
        import zipfile
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "scripts").mkdir()
            (root / "Artifacts").mkdir()
            expected = {"CFBundleIdentifier": "local.macplaza.app", "CFBundleShortVersionString": "0.21.0",
                        "CFBundleVersion": "35", "SUPublicEDKey": "expected-key"}
            (root / "scripts/Info.plist").write_bytes(plistlib.dumps(expected))
            with zipfile.ZipFile(root / "Artifacts/Mac-Plaza-0.21.0.zip", "w") as archive:
                archive.writestr("Mac Plaza.app/Contents/Info.plist", plistlib.dumps(dict(expected, SUPublicEDKey="changed-key")))
            real_run = subprocess.run
            def run(command, **kwargs):
                if command[0] == "codesign":
                    return subprocess.CompletedProcess(command, 0, stdout="", stderr="Signature=adhoc\n")
                return real_run(command, **kwargs)
            with patch.object(verify_release.subprocess, "run", side_effect=run), self.assertRaisesRegex(SigningError, "SUPublicEDKey"):
                verify_release.verify_release(root, testing_preview=True)

    def test_accepts_exact_identity_or_fingerprint_from_pinned_team(self):
        self.assertEqual(select_identity(IDENTITIES, NAME, "Application", TEAM), HASH)
        self.assertEqual(select_identity(IDENTITIES, HASH.lower(), "Application", TEAM), HASH)

    def test_rejects_wrong_team_development_and_installer_certificate_for_app(self):
        for name in [NAME.replace(TEAM, "B123456789"), NAME.replace("Developer ID Application", "Apple Development"),
                     NAME.replace("Application", "Installer")]:
            with self.subTest(name=name), self.assertRaises(SigningError):
                select_identity(IDENTITIES.replace(NAME, name), name, "Application", TEAM)

    def test_rejects_missing_private_identity_ambiguous_name_and_unconfigured_team(self):
        for output, team in [("0 valid identities found", TEAM), (IDENTITIES + IDENTITIES, TEAM), (IDENTITIES, "")]:
            with self.subTest(output=output), self.assertRaises(SigningError):
                select_identity(output, NAME, "Application", team)

    def test_accepts_changed_binary_hash_with_same_stable_requirement(self):
        check_metadata(METADATA, REQUIREMENT, TEAM)
        check_metadata(METADATA.replace("0123456789", "fedcba9876"), REQUIREMENT, TEAM)

    def test_accepts_apples_unquoted_team_requirement_without_accepting_a_prefix(self):
        unquoted = REQUIREMENT.replace('"' + TEAM + '"', TEAM)
        check_metadata(METADATA, unquoted, TEAM)
        with self.assertRaises(SigningError):
            check_metadata(METADATA, unquoted.replace(TEAM, TEAM + "EXTRA"), TEAM)

    def test_rejects_missing_runtime_timestamp_wrong_team_and_changed_identifier(self):
        for metadata in [METADATA.replace("(runtime)", ""), METADATA.replace("Timestamp=", "MissingTimestamp="),
                         METADATA.replace(TEAM, "B123456789"), METADATA.replace("local.macplaza.app", "local.macplaza.other")]:
            with self.subTest(metadata=metadata), self.assertRaises(SigningError):
                check_metadata(metadata, REQUIREMENT, TEAM)

    def test_rejects_hash_identity_even_if_other_metadata_looks_valid(self):
        with self.assertRaises(SigningError):
            check_metadata(METADATA, 'designated => cdhash H"abc123"', TEAM)

    def test_preserves_helper_sandbox_entitlements_but_removes_debug_access(self):
        entitlements = {"com.apple.security.app-sandbox": True, "com.apple.security.network.client": True,
                        "com.apple.security.get-task-allow": True}
        result = subprocess.CompletedProcess([], 0, stdout=plistlib.dumps(entitlements), stderr=b"")
        with patch.object(sign_app.subprocess, "run", return_value=result):
            actual = sign_app.release_entitlements(Path("Helper.xpc"))
        self.assertEqual(actual, {"com.apple.security.app-sandbox": True, "com.apple.security.network.client": True})

    def test_stops_if_existing_entitlements_cannot_be_inspected(self):
        result = subprocess.CompletedProcess([], 1, stdout=b"", stderr=b"signature corrupt")
        with patch.object(sign_app.subprocess, "run", return_value=result), self.assertRaises(SigningError):
            sign_app.release_entitlements(Path("Helper.xpc"))

    def test_signs_nested_code_before_bundles_and_skips_resource_files_and_symlinks(self):
        with tempfile.TemporaryDirectory() as directory:
            app = Path(directory) / "Mac Plaza.app"
            helper = app / "Contents/Frameworks/Sparkle.framework/Versions/B/Helper.xpc"
            binary = helper / "Contents/MacOS/Helper"
            binary.parent.mkdir(parents=True)
            binary.write_bytes(bytes.fromhex("cffaedfe") + b"example")
            (app / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": "local.macplaza.app"}))
            (app / "Contents/Resources").mkdir()
            (app / "Contents/Resources/texture.dat").write_bytes(b"image")
            link = app / "Contents/Frameworks/HelperLink"
            link.symlink_to(binary)
            called = []
            with patch.object(sign_app, "find_identity", return_value=HASH), \
                 patch.object(sign_app, "release_entitlements", return_value={}), \
                 patch.object(sign_app, "verify_app") as verify, \
                 patch.object(sign_app.subprocess, "run", side_effect=lambda command, **kwargs: called.append(command)):
                sign_app.sign_app(app, NAME, TEAM)
            paths = [Path(command[-1]) for command in called]
            self.assertLess(paths.index(binary), paths.index(helper))
            self.assertEqual(paths[-1], app)
            self.assertNotIn(link, paths)
            self.assertNotIn(app / "Contents/Resources/texture.dat", paths)
            for command in called:
                self.assertIn("runtime", command)
                self.assertIn("--timestamp", command)
                self.assertIn("--preserve-metadata=identifier", command)
                self.assertEqual(command[command.index("--sign") + 1], HASH)
            verify.assert_called_once_with(app, TEAM)


if __name__ == "__main__":
    unittest.main()
