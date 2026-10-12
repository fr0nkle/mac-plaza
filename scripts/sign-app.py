"""Sign embedded Mach-O code and bundles inside-out for Developer ID releases."""
from pathlib import Path
import subprocess
import sys

app = Path(sys.argv[1]).resolve()
identity = sys.argv[2]
magic = {b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca'}
def sign(path):
    subprocess.run(['codesign', '--force', '--sign', identity, '--options', 'runtime', '--timestamp', str(path)], check=True)
for path in sorted(app.rglob('*'), key=lambda p: len(p.parts), reverse=True):
    if path.is_symlink(): continue
    if path.is_file():
        with path.open('rb') as stream: header = stream.read(4)
        if header in magic: sign(path)
    elif path.suffix in ('.app', '.xpc', '.framework'): sign(path)
sign(app)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], check=True)
