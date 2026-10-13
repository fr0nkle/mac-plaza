"""Isolated real Plaza HTTP service. Credentials stay in the test process pipe."""
import json
from pathlib import Path
import sys
import uuid

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'Server'))
from server import PlazaService, make_server
from test_server import avatar

service = PlazaService(':memory:', 'http://127.0.0.1:8787', 'test', 'test')
windows = service.create_session('10001', 'Windows Friend')['token']
mac = service.create_session('10002', 'Mac Friend')['token']
stranger = service.create_session('10003', 'Stranger')['token']
def call(token, method, route, **body):
    return service.handle(method, '/v1/' + route, body, token)
appearance = avatar()
appearance['id'] = str(uuid.uuid4())
appearance['name'] = 'Mac Mii'
for token in (windows, mac):
    call(token, 'PUT', 'profile', avatar=appearance, note='', sharing=True, sharePresence=True)
code = call(mac, 'POST', 'invites')['code']
call(windows, 'POST', 'friends/request', code=code)
windows_id = call(windows, 'GET', 'snapshot')['account']['id']
call(mac, 'POST', 'friends/accept', id=windows_id)
note = dict(id=str(uuid.uuid4()), author=appearance, text='Hello Windows, from Mac!', drawing=[],
            drawingDescription='', created=1234567890,
            topic=dict(label='Portal 2', bundleID='com.valvesoftware.portal2', steamAppID=620))
call(mac, 'PUT', 'notes', notes=[note])
server = make_server(service, port=0)
origin = 'http://127.0.0.1:' + str(server.server_address[1])
service.public_url = origin
print(json.dumps(dict(origin=origin, windows=windows, mac=mac, stranger=stranger, accountID=windows_id, macNote=note)), flush=True)
server.serve_forever()
