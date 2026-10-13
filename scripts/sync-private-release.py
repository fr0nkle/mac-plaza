"""Pull new private GitHub prereleases onto the developer's Mac for app updates."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
gh = os.environ.get('PLAZA_GH', str(root / 'Server/.tools/gh'))
repo = 'fr0nkle/mac-plaza'
def query(*args):
    return subprocess.check_output([gh, *args], text=True)
if query('repo', 'view', repo, '--json', 'isPrivate', '--jq', '.isPrivate').strip() != 'true':
    raise SystemExit('Repository must remain private.')
releases = json.loads(query('api', 'repos/' + repo + '/releases?per_page=30'))
releases = [release for release in releases if not release['draft']]
if not releases: raise SystemExit(0)
latest = releases[0]
destination = root / 'Server/.updates'; destination.mkdir(mode=0o700, exist_ok=True)
if (destination / 'release.json').exists():
    current = json.loads((destination / 'release.json').read_text())
    if latest['tag_name'] == 'v' + current['version']: raise SystemExit(0)
with tempfile.TemporaryDirectory(prefix='macplaza-update-') as temporary:
    query('release', 'download', latest['tag_name'], '--repo', repo, '--dir', temporary,
          '--pattern', 'release.json', '--pattern', 'Mac-Plaza-*.zip', '--pattern', 'Mac-Plaza-*.dmg')
    staging = Path(temporary)
    import sys
    sys.path.insert(0, str(root / 'Server'))
    from updates import ReleaseStore
    manifest = ReleaseStore(staging).manifest()
    if (destination / 'release.json').exists() and int(manifest['build']) <= int(current['build']):
        raise SystemExit('Refusing an older or reused build number.')
    for key, checksum in (('archive', 'sha256'), ('source', 'sourceSHA256')):
        asset = ReleaseStore(staging).asset(manifest[key])
        if hashlib.sha256(asset.read_bytes()).hexdigest() != manifest[checksum]:
            raise SystemExit('Release checksum failed.')
    subprocess.run([str(root / 'ThirdParty/Sparkle/bin/sign_update'), '--account', 'macplaza-updates', '--verify',
                    str(staging / manifest['archive']), manifest['signature']], check=True, stdout=subprocess.DEVNULL)
    for key in ('archive', 'source'):
        partial = destination / (manifest[key] + '.tmp')
        shutil.copyfile(staging / manifest[key], partial); os.chmod(partial, 0o600)
        partial.replace(destination / manifest[key])
    partial = destination / 'release.json.tmp'; shutil.copyfile(staging / 'release.json', partial)
    partial.replace(destination / 'release.json')
    from public_releases import stage
    installer = staging / ('Mac-Plaza-' + manifest['version'] + '.dmg')
    if installer.is_file() and manifest.get('installerSHA256'):
        if hashlib.sha256(installer.read_bytes()).hexdigest() != manifest['installerSHA256']:
            raise SystemExit('Installer checksum failed.')
        stage(root / 'Server/.downloads', installer, staging / manifest['source'], manifest['version'], manifest['build'])
print('Private update ready:', latest['tag_name'])
