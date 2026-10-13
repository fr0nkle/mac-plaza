"""Publish Windows page metadata only after verifying downloaded release assets."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil

root = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser()
parser.add_argument('assets', type=Path)
parser.add_argument('--github-release', type=Path, help='GitHub REST release metadata, including uploaded asset digests')
args = parser.parse_args()
version = json.loads((root / 'Windows/package.json').read_text())['version']
if not re.fullmatch(r'\d+\.\d+\.\d+', version):
    raise SystemExit('Invalid Windows version.')
origin = 'https://github.com/fr0nkle/mac-plaza/releases/download/windows-v' + version
checksums = {}
for line in (args.assets / 'SHA256SUMS.txt').read_text().splitlines():
    digest, filename = line.split(maxsplit=1)
    checksums[filename.lstrip('*')] = digest
windows = dict(version=version)
published = json.loads(args.github_release.read_text()) if args.github_release else None
if published and (published.get('tag_name') != 'windows-v' + version or published.get('draft') is not False):
    raise SystemExit('Expected the published Windows release.')
for kind, filename in (
    ('installer', f'Plaza-Windows-{version}-Setup-x64.exe'),
    ('portable', f'Plaza-Windows-{version}-x64.zip'),
    ('source', f'Plaza-Windows-{version}-Source.zip'),
):
    if published:
        asset = next((a for a in published['assets'] if a['name'] == filename), None)
        if not asset or asset.get('state') != 'uploaded' or asset.get('browser_download_url') != origin + '/' + filename or asset.get('size', 0) <= 0:
            raise SystemExit('Missing or incomplete GitHub Windows asset.')
        checksum = asset.get('digest', '').removeprefix('sha256:')
        size = asset['size']
    else:
        file = args.assets / filename
        digest = hashlib.sha256()
        with file.open('rb') as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b''):
                digest.update(block)
        checksum, size = digest.hexdigest(), file.stat().st_size
    if not re.fullmatch(r'[a-f0-9]{64}', checksum) or checksums.get(filename) != checksum:
        raise SystemExit('Windows asset checksum mismatch; page not changed.')
    windows[kind] = dict(url=origin + '/' + filename, size=size, sha256=checksum)
site = root / 'Website'
html = (site / 'index.html').read_text()
for css, kind in (('button windows-download','installer'), ('windows-portable','portable'), ('windows-source-download','source')):
    html, count = re.subn(r'(<a class="' + re.escape(css) + r'" href=")[^"]+', lambda match: match[1] + windows[kind]['url'], html)
    if count != 1:
        raise SystemExit('Windows download link missing; page not changed.')
html = re.sub(r'(<p id="windows-release-status"[^>]*>)[^<]+',lambda m:m[1]+f'Version {version} · {round(windows["installer"]["size"]/1048576)} MB · Testing preview',html)
metadata = json.loads((site / 'release.json').read_text())
metadata['windows'] = windows
(site / 'index.html').write_text(html)
(site / 'release.json').write_text(json.dumps(metadata, indent=2) + '\n')
print('Windows download checksums verified and website source updated.')
