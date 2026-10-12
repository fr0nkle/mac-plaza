import base64
import json
import os
from pathlib import Path
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
from unittest.mock import patch
from server import PlazaService, make_server
from updates import ReleaseStore


class UpdateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.archive = self.root / "Mac-Plaza-0.13.0.zip"
        self.archive.write_bytes(b"test signed archive")
        self.manifest = dict(version="0.13.0", build="15", archive=self.archive.name,
                             signature=base64.b64encode(b"x" * 64).decode(), length=self.archive.stat().st_size)
        (self.root / "release.json").write_text(json.dumps(self.manifest))
        self.store = ReleaseStore(self.root)

    def tearDown(self):
        self.temp.cleanup()

    def test_appcast_has_signed_same_origin_enclosure(self):
        feed = ET.fromstring(self.store.appcast("https://plaza.example"))
        enclosure = feed.find("channel/item/enclosure")
        self.assertEqual(enclosure.attrib["url"], "https://plaza.example/updates/" + self.archive.name)
        self.assertEqual(enclosure.attrib["{http://www.andymatuschak.org/xml-namespaces/sparkle}version"], "15")
        self.assertEqual(enclosure.attrib["{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature"], self.manifest["signature"])

    def test_incomplete_invalid_or_outside_release_is_rejected(self):
        for key, value in (("length", 99), ("archive", "../private.zip"), ("signature", "bad"), ("build", "<script>")):
            broken = dict(self.manifest, **{key: value})
            (self.root / "release.json").write_text(json.dumps(broken))
            with self.assertRaises((ValueError, OSError)):
                self.store.manifest()
        with self.assertRaises(ValueError): self.store.asset("../../.env")

    def test_http_feed_and_archives_require_a_live_plaza_session(self):
        service = PlazaService(":memory:", "http://127.0.0.1:8787")
        token = service.create_session("100", "Tester")["token"]
        server = make_server(service, port=0)
        thread = threading.Thread(target=server.serve_forever, daemon=True); thread.start()
        try:
            with patch.dict(os.environ, {"PLAZA_UPDATES": str(self.root)}):
                base = "http://127.0.0.1:" + str(server.server_port) + "/updates/"
                for path in ("appcast.xml", self.archive.name):
                    with self.assertRaises(urllib.error.HTTPError) as denied:
                        urllib.request.urlopen(base + path)
                    self.assertEqual(denied.exception.code, 401)
                    req = urllib.request.Request(base + path, headers={"Authorization": "Bearer " + token})
                    with urllib.request.urlopen(req) as response:
                        self.assertEqual(response.status, 200)
                        content = response.read()
                        self.assertTrue(content)
                service.handle("POST", "/v1/logout", {}, token)
                with self.assertRaises(urllib.error.HTTPError) as denied:
                    urllib.request.urlopen(req)
                self.assertEqual(denied.exception.code, 401)
        finally:
            server.shutdown(); server.server_close(); thread.join(); service.db.close()
