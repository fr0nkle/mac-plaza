import tempfile
import unittest
from pathlib import Path

from login_start import refresh_environment


class HostingRefreshTests(unittest.TestCase):
    def test_repeated_refresh_preserves_interpreter_links_and_refreshes_packages(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source, destination = root / "source", root / "runtime"
            (source / "bin").mkdir(parents=True)
            interpreter = root / "system-python"
            interpreter.write_bytes(b"system executable must remain untouched")
            (source / "bin/python3").symlink_to(interpreter)
            (source / "bin/python").symlink_to("python3")
            package = source / "lib/package.py"
            package.parent.mkdir()
            package.write_text("first")
            refresh_environment(source, destination)
            package.write_text("updated")
            refresh_environment(source, destination)
            self.assertTrue((destination / "bin/python").is_symlink())
            self.assertTrue((destination / "bin/python3").is_symlink())
            self.assertEqual((destination / "lib/package.py").read_text(), "updated")
            self.assertEqual(interpreter.read_bytes(), b"system executable must remain untouched")
