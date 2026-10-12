#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
exec .venv/bin/python - <<'PY'
import json, os, signal, subprocess
from pathlib import Path
record = Path('.run/processes.json')
if not record.exists():
    raise SystemExit('No recorded friend-test processes. Stop manually started services in their own terminals.')
for item in json.loads(record.read_text()):
    pid = str(item['pid'])
    try:
        command = subprocess.check_output(['ps', '-wwp', pid, '-o', 'command='], text=True).strip()
        cwd = subprocess.check_output(['lsof', '-a', '-p', pid, '-d', 'cwd', '-Fn'], text=True)
    except subprocess.CalledProcessError:
        continue
    if command == item['command'] and 'n' + item['cwd'] in cwd.splitlines():
        os.kill(item['pid'], signal.SIGTERM)
        print('Stopped Plaza test ' + item['kind'] + '.')
print('Your local database and Discord application are preserved.')
PY
