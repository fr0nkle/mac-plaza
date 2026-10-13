'use strict';
const { app, BrowserWindow, ipcMain, shell, safeStorage, dialog, Menu } = require('electron');
const fs = require('node:fs/promises');
const path = require('node:path');
const { randomBytes, createHash } = require('node:crypto');
const core = require('./core.cjs');
let window, store, session = null, login = null;
let operation = Promise.resolve();
const root = () => app.getPath('userData');
const filename = () => path.join(root(), 'plaza.json');
async function atomic(file, data) {
  await fs.mkdir(path.dirname(file), { recursive: true });
  await fs.writeFile(file + '.tmp', data, { mode: 0o600 });
  await fs.rename(file + '.tmp', file);
}
async function save() { await atomic(filename(), JSON.stringify(store)); }
function key() { return session ? `${session.origin}/${session.accountID}` : 'offline'; }
function doc() { return store.accounts[key()] ||= core.document(); }
function publicState() { return { connected: !!session, origin: session?.origin || store.origin, document: doc(), version: app.getVersion() }; }
async function persistSession() {
  if (!safeStorage.isEncryptionAvailable()) throw new Error('Windows credential encryption is unavailable. Sign-in was not saved.');
  await atomic(path.join(root(), 'session.bin'), safeStorage.encryptString(JSON.stringify(session)));
}
async function request(method, route, body, auth = session) {
  if (!auth) throw new Error('Connect Discord first.');
  const headers = { 'Content-Type': 'application/json' };
  if (auth.token) headers.Authorization = 'Bearer ' + auth.token;
  let response;
  try { response = await fetch(core.endpoint(auth.origin) + route, { method, headers,
    body: body === undefined ? undefined : JSON.stringify(body), redirect: 'error', signal: AbortSignal.timeout(20000) }); }
  catch { throw new Error('The Plaza service is unavailable. Your saved notes and draft are safe. Try again when it is online.'); }
  const text = await response.text();
  if (text.length > 8_000_000) throw new Error('Service response is too large.');
  let data; try { data = JSON.parse(text); } catch { throw new Error('The service returned an unreadable response.'); }
  if (!response.ok) { const error = new Error(data.error || 'The service rejected the request.'); error.status = response.status; throw error; }
  return data;
}
async function refresh() {
  if (!session) return { ...publicState(), snapshot: null, notes: [] };
  const snapshot = await request('GET', '/v1/snapshot');
  const threads = await request('GET', '/v1/notes/threads');
  doc().remoteNotes = threads.notes;
  await save();
  return { ...publicState(), snapshot, notes: threads.notes };
}
async function sync() {
  if (!session || !Object.keys(doc().pending).length) return refresh();
  const { notes } = await request('GET', '/v1/notes/owned');
  await request('PUT', '/v1/notes', { notes: core.mergeNotes(notes, session.accountID, doc().pending) });
  doc().pending = {}; await save();
  return refresh();
}
const actions = {
  state: async () => publicState(),
  refresh: sync,
  blocks: async () => request('GET', '/v1/blocks'),
  draft: async value => {
    if (typeof value.text !== 'string' || value.text.length > 1000 || !Array.isArray(value.drawing) || JSON.stringify(value).length > 2_000_000) throw new Error('Draft is too large.');
    doc().draft = value; await save(); return {};
  },
  profile: async value => {
    // Import appearance only, using the same bounded fields as the Mac service.
    core.validateAvatar(value);
    if (JSON.stringify(value).length > 20000) throw new Error('Character file is too large.');
    doc().avatar = value; await save();
    if (session) await request('PUT', '/v1/profile', { avatar: value, note: '', sharing: true, sharePresence: true, shareActivity: false, shareDiscordFriends: false });
    return publicState();
  },
  note: async value => {
    core.validateNote(value.note);
    if (value.visibility === 'public') {
      if (!session) throw new Error('Connect Discord before sharing with friends.');
      doc().pending[value.note.id] = value.note;
      doc().privateNotes = doc().privateNotes.filter(n => n.id !== value.note.id);
    } else {
      if (!doc().privateNotes.some(n => n.id === value.note.id) && doc().privateNotes.length >= 200) throw new Error('The private journal is full.');
      doc().privateNotes = doc().privateNotes.filter(n => n.id !== value.note.id).concat(value.note);
      if (session) doc().pending[value.note.id] = null;
    }
    doc().draft = { text: '', drawing: [], drawingDescription: '' }; await save();
    return sync();
  },
  deleteNote: async id => {
    doc().privateNotes = doc().privateNotes.filter(n => n.id !== id);
    if (session) doc().pending[id] = null;
    await save(); return sync();
  },
  invite: async () => request('POST', '/v1/invites', {}),
  friend: async value => {
    if (!['request', 'accept', 'remove', 'block', 'unblock'].includes(value.action)) throw new Error('Unknown friend action.');
    await request('POST', '/v1/friends/' + value.action, value.action === 'request' ? { code: value.code } : { id: value.id });
    return refresh();
  },
  like: async value => { await request('PUT', `/v1/notes/${validID(value.id)}/like`, { liked: !!value.liked }); return refresh(); },
  reply: async value => {
    await request(value.remove ? 'DELETE' : 'PUT', `/v1/notes/${validID(value.noteID)}/replies/${validID(value.id)}`, { author: doc().avatar, text: value.text });
    return refresh();
  },
  authStart: async origin => {
    if (session) throw new Error('Disconnect the current account first.');
    origin = core.endpoint(origin); store.origin = origin; await save();
    const verifier = randomBytes(32).toString('base64url');
    const result = await request('POST', '/v1/auth/start', { challenge: createHash('sha256').update(verifier).digest('base64url'), friendDiscovery: false }, { origin });
    const url = new URL(result.authorizeURL);
    if (url.origin !== 'https://discord.com' || url.pathname !== '/oauth2/authorize') throw new Error('Unexpected Discord authorization address.');
    login = { origin, verifier, state: result.state, expires: Date.now() + 300000 };
    await shell.openExternal(url.href); return {};
  },
  authFinish: async () => {
    if (!login || Date.now() > login.expires) { login = null; throw new Error('Sign-in expired. Connect Discord again.'); }
    let result;
    try { result = await request('POST', '/v1/auth/finish', { state: login.state, verifier: login.verifier }, { origin: login.origin }); }
    catch (error) { if ([401, 409].includes(error.status)) return { waiting: true }; throw error; }
    const auth = { origin: login.origin, token: result.token };
    const snapshot = await request('GET', '/v1/snapshot', undefined, auth);
    auth.accountID = snapshot.account.id;
    session = auth; login = null;
    if (!store.accounts[key()]) {
      store.accounts[key()] = core.document();
      if (snapshot.account.avatar) doc().avatar = snapshot.account.avatar;
      else doc().avatar = structuredClone(store.accounts.offline.avatar);
    }
    await persistSession(); await save(); return refresh();
  },
  logout: async () => {
    // Revoke if reachable; always remove this device's encrypted credential.
    try { if (session) await request('POST', '/v1/logout', {}); } catch { /* local disconnect still works offline */ }
    session = null; login = null; await fs.rm(path.join(root(), 'session.bin'), { force: true });
    return publicState();
  },
  importMii: async () => {
    const result = await dialog.showOpenDialog(window, { filters: [{ name: 'Mac Plaza character JSON', extensions: ['json'] }], properties: ['openFile'] });
    if (result.canceled) return null;
    const file = result.filePaths[0];
    if ((await fs.stat(file)).size > 20000) throw new Error('Character file is too large.');
    const value = JSON.parse(await fs.readFile(file, 'utf8'));
    return actions.profile(value);
  },
  exportMii: async () => {
    const result = await dialog.showSaveDialog(window, { defaultPath: 'Plaza-Mii.json', filters: [{ name: 'Character JSON', extensions: ['json'] }] });
    if (!result.canceled) await fs.writeFile(result.filePath, JSON.stringify(doc().avatar, null, 2));
    return {};
  },
  website: async () => { await shell.openExternal('https://plaza.squidproductions.org'); return {}; }
};
function validID(id) { if (typeof id !== 'string' || !/^[\da-f]{8}-(?:[\da-f]{4}-){3}[\da-f]{12}$/i.test(id)) throw new Error('Invalid note identity.'); return id; }
app.whenReady().then(async () => {
  try { store = JSON.parse(await fs.readFile(filename(), 'utf8')); if (!store.accounts.offline) throw new Error('Invalid saved plaza.'); }
  catch (error) {
    if (error.code !== 'ENOENT') {
      dialog.showErrorBox('Saved plaza could not be read', 'Your plaza was preserved. Restore plaza.json from a backup before reopening.'); app.quit(); return;
    }
    store = { origin: core.DEFAULT_SERVICE, accounts: { offline: core.document() } }; await save();
  }
  try { session = JSON.parse(safeStorage.decryptString(await fs.readFile(path.join(root(), 'session.bin')))); core.endpoint(session.origin); validID(session.accountID); }
  catch { session = null; }
  ipcMain.handle('plaza', (event, action, value) => {
    if (event.sender !== window.webContents || event.senderFrame !== window.webContents.mainFrame || !Object.hasOwn(actions, action)) throw new Error('Unsupported request.');
    const next = operation.then(async () => {
      try { return { ok: true, value: await actions[action](value) }; }
      catch (error) { return { ok: false, error: error.message }; }
    });
    operation = next.catch(() => {}); return next;
  });
  window = new BrowserWindow({ width: 1240, height: 850, minWidth: 800, minHeight: 620, title: 'Plaza', backgroundColor: '#f1f7f9',
    webPreferences: { preload: path.join(__dirname, 'preload.cjs'), contextIsolation: true, sandbox: true, nodeIntegration: false } });
  Menu.setApplicationMenu(Menu.buildFromTemplate([{ label: 'Plaza', submenu: [{ label: 'Downloads & updates', click: actions.website }, { role: 'quit' }] },
    { label: 'Edit', submenu: [{ role: 'undo' }, { role: 'redo' }, { type: 'separator' }, { role: 'cut' }, { role: 'copy' }, { role: 'paste' }, { role: 'selectAll' }] },
    { label: 'View', submenu: [{ role: 'resetZoom' }, { role: 'zoomIn' }, { role: 'zoomOut' }, { role: 'togglefullscreen' }] }]));
  window.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  window.webContents.on('will-navigate', event => event.preventDefault());
  window.webContents.session.setPermissionRequestHandler((_contents, _permission, callback) => callback(false));
  await window.loadFile(path.join(__dirname, 'index.html'));
});
app.on('window-all-closed', () => app.quit());
