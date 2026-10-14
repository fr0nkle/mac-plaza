"""Prepare versioned GitHub download links; publish the Site separately."""
import hashlib
import json
from pathlib import Path
import re
import shutil
import zipfile

root = Path(__file__).resolve().parent.parent
release = json.loads((root / 'Artifacts/release.json').read_text())
version = release['version']
if not re.fullmatch(r'\d+(?:\.\d+)*', version):
    raise SystemExit('Invalid release version.')
origin = 'https://github.com/fr0nkle/mac-plaza/releases/download/v' + version
public = {'version': version}
for kind, filename, checksum in (
    ('installer', f'Mac-Plaza-{version}.dmg', 'installerSHA256'),
    ('source', f'Mac-Plaza-{version}-Source.zip', 'sourceSHA256'),
):
    asset = root / 'Artifacts' / filename
    digest = hashlib.sha256()
    with asset.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(block)
    if digest.hexdigest() != release[checksum]:
        raise SystemExit(f'{kind} checksum failed; page not changed.')
    public[kind] = {'url': origin + '/' + filename, 'size': asset.stat().st_size,
                    'sha256': digest.hexdigest()}

# A public release must use the distribution build and sanitized source bundle.
recordings = ('arrival-drop.wav', 'arrival-wave.wav', 'mii-maker.m4a', 'warawara-home.m4a')
for filename in (release['archive'], release['source']):
    if Path(filename).name != filename:
        raise SystemExit('Invalid release archive name.')
    with zipfile.ZipFile(root / 'Artifacts' / filename) as archive:
        for name in archive.namelist():
            if '/Audio/' in name and name.endswith(recordings):
                raise SystemExit('Local Nintendo recording in release; rebuild with PLAZA_DISTRIBUTION=1.')
            if filename == release['source'] and 'ThirdParty/DiscordSocialSDK/discord_social_sdk/' in name:
                raise SystemExit('Standalone Discord SDK in source archive.')

site = root / 'Website'
html = (site / 'index.html').read_text()
html, count = re.subn(r'(<a class="button download" href=")[^"]+',
                     lambda match: match[1] + public['installer']['url'], html)
if count not in (1, 2):
    raise SystemExit('Expected one or two installer links; page not changed.')
html, count = re.subn(r'(<a class="source-download" href=")[^"]+',
                     lambda match: match[1] + public['source']['url'], html)
if count != 1:
    raise SystemExit('Expected a corresponding-source link; page not changed.')
html = re.sub(r'(<a class="release-notes" href=")[^"]+',
              lambda match: match[1] + 'https://github.com/fr0nkle/mac-plaza/releases/tag/v' + version, html)
html = re.sub(r'(<p id="release-status"[^>]*>)[^<]+',
              lambda match: match[1] + f'Version {version} · {round(public["installer"]["size"] / 1048576)} MB', html)
(site / 'index.html').write_text(html)
(site / 'release.json').write_text(json.dumps(public, indent=2) + '\n')
checkout = root / 'DownloadSite/dist'
if (root / 'DownloadSite/.openai/hosting.json').is_file():
    for asset in site.iterdir():
        if asset.is_file():
            shutil.copy2(asset, checkout / asset.name)
print(f'Prepared website links for {version}. Deploy the updated Site to publish them.')
