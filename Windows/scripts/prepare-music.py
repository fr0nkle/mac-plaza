"""Stage existing local Mac audio for private Windows review; never downloads."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--source', required=True, type=Path, help='Existing Mac Resources/Audio folder')
parser.add_argument('--output', type=Path, default=Path(__file__).resolve().parents[1] / 'native/runtime/Audio')
args = parser.parse_args()
files = ['warawara-home.m4a', 'mii-maker.m4a', 'friends-menu.m4a', 'system-settings.m4a', 'note-writing.m4a', 'miiverse.m4a', 'miiverse-alternate.m4a', 'UI/click.wav', 'UI/back.wav']
manifest = []
for name in files:
    source = args.source / name
    if not source.is_file() or not 0 < source.stat().st_size <= 256 * 1024 * 1024:
        parser.error(f'Missing or out-of-range local audio: {name}')
    manifest.append({'file': name, 'sha256': hashlib.sha256(source.read_bytes()).hexdigest()})
for name in files:
    target = args.output / name
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(args.source / name, target)
(args.output / 'SOURCE.json').write_text(json.dumps({'source': 'Existing local Mac Resources/Audio; separate soundtrack rights apply. Private staging only.', 'files': manifest}, indent=2) + '\n')
print(f'Staged {len(files)} existing local recordings; no network access.')
