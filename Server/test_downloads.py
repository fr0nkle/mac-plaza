import json
import os
from pathlib import Path
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from unittest.mock import patch

from downloads import DownloadStore
from server import PlazaService, make_server


class DownloadTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.now = 1000
        self.store = DownloadStore(self.root / "downloads", now=lambda: self.now)
        self.zip = self.root / "Mac Plaza - Friend Test (0.13.2).zip"
        self.content = b"test zip content for resumable downloads"
        self.zip.write_bytes(self.content)
        self.token, self.metadata = self.store.create(self.zip)

    def tearDown(self):
        self.temp.cleanup()

    def test_expiry_revocation_and_hash_only_registry(self):
        record = self.store.root / (self.store.key(self.token) + ".json")
        self.assertNotIn(self.token, record.read_text())
        self.assertEqual(self.store.resolve(self.token)[0].read_bytes(), self.content)
        self.now += 7 * 86400
        with self.assertRaises(FileNotFoundError):
            self.store.resolve(self.token)
        self.now = 1000
        self.store.revoke(self.token)
        with self.assertRaises(FileNotFoundError):
            self.store.resolve(self.token)

    def test_unknown_tokens_traversal_and_asset_symlinks_are_denied(self):
        for token in ("", "../.env", "a" * 43, self.token + "/extra"):
            with self.assertRaises(FileNotFoundError):
                self.store.resolve(token)
        asset, _ = self.store.resolve(self.token)
        asset.unlink()
        asset.symlink_to(self.zip)
        with self.assertRaises(FileNotFoundError):
            self.store.resolve(self.token)

    def test_http_download_head_resume_and_private_api_stays_authenticated(self):
        # Use a live token for the real-clock HTTP store.
        token, data = DownloadStore(self.store.root).create(self.zip)
        service = PlazaService(":memory:", "http://127.0.0.1:8787")
        server = make_server(service, port=0)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        base = "http://127.0.0.1:" + str(server.server_port)
        url = base + "/download/" + token

        def fetch(headers=None, method="GET"):
            return urllib.request.urlopen(urllib.request.Request(url, headers=headers or {}, method=method))

        try:
            with patch.dict(os.environ, {"PLAZA_DOWNLOADS": str(self.store.root)}):
                with fetch() as response:
                    self.assertEqual(response.status, 200)
                    self.assertEqual(response.read(), self.content)
                    self.assertEqual(response.headers["Cache-Control"], "private, no-store")
                    self.assertEqual(response.headers["Referrer-Policy"], "no-referrer")
                    self.assertIn(self.zip.name, response.headers["Content-Disposition"])
                    etag = response.headers["ETag"]
                with fetch({"Range": "bytes=4-9"}, "HEAD") as response:
                    self.assertEqual(response.status, 200)
                    self.assertEqual(int(response.headers["Content-Length"]), len(self.content))
                    self.assertEqual(response.read(), b"")
                for value, expected in (("bytes=4-9", self.content[4:10]),
                                        ("bytes=4-", self.content[4:]),
                                        ("bytes=-5", self.content[-5:])):
                    with fetch({"Range": value, "If-Range": etag}) as response:
                        self.assertEqual(response.status, 206)
                        self.assertEqual(response.read(), expected)
                        self.assertIn("/" + str(len(self.content)), response.headers["Content-Range"])
                with fetch({"Range": "bytes=4-9", "If-Range": '"other"'}) as response:
                    self.assertEqual(response.status, 200)
                    self.assertEqual(response.read(), self.content)
                for value in ("bytes=999-", "bytes=8-2", "bytes=0-1,4-5", "bytes=-0"):
                    with self.assertRaises(urllib.error.HTTPError) as denied:
                        fetch({"Range": value})
                    self.assertEqual(denied.exception.code, 416)
                with self.assertRaises(urllib.error.HTTPError) as denied:
                    fetch({"Origin": "https://unrelated.example"})
                self.assertEqual(denied.exception.code, 403)
                for path, status in (("/download/" + "a" * 43, 404),
                                     ("/download/../.env", 404), ("/updates/appcast.xml", 401)):
                    with self.assertRaises(urllib.error.HTTPError) as denied:
                        urllib.request.urlopen(base + path)
                    self.assertEqual(denied.exception.code, status)
                DownloadStore(self.store.root).revoke(token)
                with self.assertRaises(urllib.error.HTTPError) as denied:
                    fetch()
                self.assertEqual(denied.exception.code, 404)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()
            service.db.close()
