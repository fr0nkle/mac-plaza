import json
import os
from pathlib import Path
import tempfile
import threading
import unittest
import urllib.request
import urllib.error
from unittest.mock import patch
from public_releases import stage, current
from downloads import DownloadStore
from server import PlazaService, make_server


class PublicReleaseTests(unittest.TestCase):
    def test_public_downloads_are_explicit_scoped_and_do_not_expire(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory); downloads=root/'downloads'
            installer=root/'Mac-Plaza-0.13.3.dmg';installer.write_bytes(b'disk image')
            source=root/'Mac-Plaza-0.13.3-Source.zip';source.write_bytes(b'corresponding source')
            stage(downloads, installer, source, '0.13.3', '18')
            release=current(downloads)
            for asset in release['files'].values():
                self.assertEqual(DownloadStore(downloads, now=lambda:10**12).resolve(asset['token'])[1]['expires'],0)
            service=PlazaService(':memory:','http://127.0.0.1:8787')
            server=make_server(service,port=0);thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
            base='http://127.0.0.1:'+str(server.server_port)
            try:
                with patch.dict(os.environ,{'PLAZA_DOWNLOADS':str(downloads)}):
                    request=urllib.request.Request(base+'/releases/latest.json',headers={'Origin':'https://plaza.example'})
                    with urllib.request.urlopen(request) as response:
                        data=json.load(response)
                        self.assertEqual(response.headers['Access-Control-Allow-Origin'],'*')
                        self.assertEqual(data['version'],'0.13.3')
                        self.assertNotIn('token',repr(data));self.assertNotIn(str(root),repr(data))
                    for key,body,mime in [('installer',b'disk image','application/x-apple-diskimage'),('source',b'corresponding source','application/zip')]:
                        with urllib.request.urlopen(base+data['files'][key]['path']) as response:
                            self.assertEqual(response.read(),body);self.assertEqual(response.headers['Content-Type'],mime)
                    for path,code in [('/releases/download/.env',404),('/updates/appcast.xml',401)]:
                        with self.assertRaises(urllib.error.HTTPError) as denied:urllib.request.urlopen(base+path)
                        self.assertEqual(denied.exception.code,code)
                    # Removing one explicitly registered file makes the release unavailable.
                    asset,_=DownloadStore(downloads).resolve(release['files']['installer']['token']);asset.unlink()
                    with self.assertRaises(urllib.error.HTTPError) as denied:urllib.request.urlopen(base+'/releases/latest.json')
                    self.assertEqual(denied.exception.code,503)
            finally:
                server.shutdown();server.server_close();thread.join();service.db.close()
