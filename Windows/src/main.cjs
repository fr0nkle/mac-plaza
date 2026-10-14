'use strict';
const { app, BrowserWindow, ipcMain, shell, safeStorage, dialog, Menu, powerMonitor, Notification, protocol, net, nativeImage, clipboard } = require('electron');
const fs = require('node:fs/promises');
const path = require('node:path');
const { randomBytes, createHash } = require('node:crypto');
const core = require('./core.cjs');
const {Engine}=require('./engine.cjs');
const {Wallpaper}=require('./wallpaper.cjs');
const {FriendRoster,validateFriends,recipients}=require('./social.cjs');
const applications=require('./apps.cjs');
const portable=require('./portable.cjs');
const {pathToFileURL}=require('node:url');
let engine,native,wallpaper,quitting=false,locked=false,suspended=false,roster=new FriendRoster(),sdk={state:'disconnected',friends:[]},games={},sdkToken='',installed=[],lastSDKRefresh=0,recoveryRequired=false;
const windows=new Set(),panels=new Map(),panelContexts=new Map(),resourceImports=new Map(),musicImports=new Map();
protocol.registerSchemesAsPrivileged([{scheme:'plaza-media',privileges:{standard:true,secure:true,supportFetchAPI:true,stream:true}}]);
let window, store, session = null, login = null;
let operation = Promise.resolve();
const root = () => app.getPath('userData');
const filename = () => path.join(root(), 'plaza.json');
async function atomic(file, data) {
  await fs.mkdir(path.dirname(file), { recursive: true });
  await fs.writeFile(file + '.tmp', data, { mode: 0o600 });
  await fs.rename(file + '.tmp', file);
}
async function save() {if(recoveryRequired)throw new Error('Restore a backup or import a plaza before saving changes.');const previous=await fs.readFile(filename()).catch(()=>null);if(previous){try{const parsed=JSON.parse(previous);if(parsed.accounts?.offline)await atomic(filename()+'.backup',previous);}catch{}}await atomic(filename(), JSON.stringify(store)); }
function key() { return session ? `${session.origin}/${session.accountID}` : 'offline'; }
function doc() { const value=store.accounts[key()] ||= core.document();value.avatars ||= [value.avatar];value.friendAssignments ||= {};value.settings ||= {};value.settings.ambientSound ??= true;return value; }
function publicState() { return { connected: !!session,recoveryRequired, origin: session?.origin || store.origin, document: doc(), version: app.getVersion(), settings:store.settings||{}, apps:store.apps||[],history:store.history||[],music:store.music||{},wallpaper:wallpaper?.state()||{supported:process.platform==='win32',active:false,interactive:true}, discord:{state:sdk.state,count:sdk.friends.length},accountID:session?.accountID }; }
function broadcast(){for(const item of windows)if(!item.isDestroyed())item.webContents.send('plaza-state',publicState());}
async function ensureSDK(){
  if(!native||!session?.discordSDK){sdk={state:session?'authorization-required':'disconnected',friends:[]};return;}
  if(session.discordSDK.expiresAt<Date.now()/1000+90){session.discordSDK=await request('POST','/v1/discord/refresh',{refreshToken:session.discordSDK.refreshToken});await persistSession();}
  if(sdkToken!==session.discordSDK.accessToken){native.configureDiscord(session.discordSDK);sdkToken=session.discordSDK.accessToken;roster.reset();}
  sdk=validateFriends(JSON.parse(native.discordSnapshot()));
}
async function audience(){if(sdk.state==='ready'&&(doc().shareProfile||(doc().remoteNotes||[]).some(n=>n.ownerID===session?.accountID))){await request('PUT','/v1/discord/recipients',{discordIDs:recipients(sdk.friends,doc().hiddenFriends)});}}
async function publishProfile(){if(session)await request('PUT','/v1/profile',{avatar:doc().avatar,note:doc().profileNote||'',sharing:!!doc().shareProfile,sharePresence:doc().sharePresence!==false,shareActivity:!!doc().shareActivity,shareDiscordFriends:!!doc().shareProfile});}
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
  await ensureSDK();
  const snapshot = await request('GET', '/v1/snapshot');
  const threads = await request('GET', '/v1/notes/threads');
  doc().remoteNotes = threads.notes;
  await audience();
  if(sdk.state==='ready'){
    if(doc().showDiscordGames&&Date.now()-lastSDKRefresh>12000){games=await request('POST','/v1/discord/games',{discordIDs:recipients(sdk.friends,doc().hiddenFriends)});lastSDKRefresh=Date.now();}
    snapshot.friends=roster.resolve(sdk.friends,snapshot,doc(),games);
    snapshot.unlinkedFriends=[];
  }
  try{await request('POST','/v1/heartbeat',{active:!locked&&!suspended,application:doc().shareActivity?store.activeApplication||null:null});}catch{}
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
    if(!doc().avatars.some(a=>a.id===value.id)&&doc().avatars.length>=100)throw new Error('The character library is full. Remove a Mii before adding another.');doc().avatar = value; await save();
    const existing=doc().avatars.findIndex(a=>a.id===value.id);if(existing>=0)doc().avatars[existing]=value;else if(doc().avatars.length<100)doc().avatars.push(value);await save();
    broadcast();try{await publishProfile();}catch(error){for(const item of windows)item.webContents.send('plaza-error','Mii saved locally. '+error.message);}
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
    const result = await request('POST', '/v1/auth/start', { challenge: createHash('sha256').update(verifier).digest('base64url'), friendDiscovery: true }, { origin });
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
    const auth = { origin: login.origin, token: result.token, discordSDK:result.discordSDK };
    const snapshot = await request('GET', '/v1/snapshot', undefined, auth);
    auth.accountID = snapshot.account.id;
    session = auth; login = null;
    if (!store.accounts[key()]) {
      store.accounts[key()] = core.document();
      if (snapshot.account.avatar) doc().avatar = snapshot.account.avatar;
      else doc().avatar = structuredClone(store.accounts.offline.avatar);
      doc().shareProfile=!!snapshot.account.shareDiscordFriends;
      doc().avatars=[doc().avatar];
    }
    await persistSession(); await save(); return refresh();
  },
  logout: async () => {
    // Revoke if reachable; always remove this device's encrypted credential.
    try { if (session) await request('POST', '/v1/logout', {}); } catch { /* local disconnect still works offline */ }
    native?.disconnectDiscord();sdkToken='';sdk={state:'disconnected',friends:[]};roster.reset();games={};
    session = null; login = null; await fs.rm(path.join(root(), 'session.bin'), { force: true });
    return publicState();
  },
  importMii: async () => {
    const result = await dialog.showOpenDialog(BrowserWindow.getFocusedWindow()||window, { filters: [{ name: 'Mii or character JSON', extensions: ['json','mii','ffsd'] }], properties: ['openFile'] });
    if (result.canceled) return null;
    const file = result.filePaths[0];
    if ((await fs.stat(file)).size > 20000) throw new Error('Character file is too large.');
    const value = path.extname(file).toLowerCase()==='.json'?JSON.parse(await fs.readFile(file,'utf8')):await engine.call('decodeMii',{data:(await fs.readFile(file)).toString('base64')});value.id=cryptoUUID();
    return actions.profile(value);
  },
  exportMii: async value => {
    core.validateAvatar(value||doc().avatar);
    const result = await dialog.showSaveDialog(window, { defaultPath: 'Plaza-Mii.json', filters: [{ name: 'Character JSON', extensions: ['json'] }] });
    if (!result.canceled) await fs.writeFile(result.filePath, JSON.stringify(value||doc().avatar, null, 2));
    return {};
  },
  copyInvite:async value=>{if(typeof value!=='string'||value.length>80)throw new Error('Invalid invitation.');clipboard.writeText(value);return{};},
  website: async () => { await shell.openExternal('https://plaza.squidproductions.org'); return {}; }
};
function cryptoUUID(){return require('node:crypto').randomUUID();}
function resourceDirectory(){return path.join(root(),'Renderer');}
Object.assign(actions,{
  scene:async args=>{const body=await fs.readFile(path.join(resourceDirectory(),'body.json'),'utf8').then(JSON.parse).catch(()=>null);const hasFFL=await fs.stat(path.join(resourceDirectory(),'FFLResHigh.dat')).then(()=>true).catch(()=>false);return engine.call('configure',{...args,clips:hasFFL?body?.animations||[]:[]});},
  engine:async value=>{if(!['renderAvatar','fallback','music','rotateHome','portable','decodeMii','encodeMii','acknowledge','cheer','arrival','finishEntrance'].includes(value.command))throw new Error('Unknown character operation.');return engine.call(value.command,value.args);},
  panel:async value=>{await openPanel(value);return{};},
  panelContext:async kind=>panelContexts.get(kind)||{},
  wallpaper:async value=>{if(value.action==='attach')await wallpaper.attach();else if(value.action==='restore')await wallpaper.restore();else if(value.action==='interactive')await wallpaper.setInteractive(value.value);else throw new Error('Unknown wallpaper action.');return publicState();},
  settings:async value=>{
    const allowed=['population','pauseMotion','pausePosts','privatePresentation','safeMode','largerText','ambientSound','musicVolume','makerMusicVolume','friendsMusicVolume','settingsMusicVolume','writingMusicVolume','rotateHome','notifications'];
    for(const [key,val]of Object.entries(value)){if(!allowed.includes(key))continue;if(key==='population'){if(!Number.isInteger(val)||val<20||val>200)throw new Error('Choose 20–200 Miis.');}else if(key.endsWith('Volume')){if(!Number.isFinite(val)||val<0||val>.35)throw new Error('Invalid volume.');}else if(typeof val!=='boolean')throw new Error('Invalid setting.');doc().settings[key]=val;}
    await save();broadcast();return publicState();
  },
  loginSettings:async value=>{store.settings ||= {};store.settings.openAtLogin=!!value.openAtLogin;store.settings.wallpaperAtLogin=!!value.wallpaperAtLogin;app.setLoginItemSettings({openAtLogin:store.settings.openAtLogin,path:process.execPath,args:store.settings.wallpaperAtLogin?['--wallpaper']:[]});await save();return publicState();},
  sharing:async value=>{doc().shareProfile=!!value.shareProfile;doc().sharePresence=!!value.sharePresence;doc().shareActivity=!!value.shareActivity;doc().showDiscordGames=!!value.showDiscordGames;if(!doc().showDiscordGames){games={};lastSDKRefresh=0;}doc().profileNote=String(value.note||'').slice(0,280);await save();await publishProfile();await audience();return refresh();},
  hideFriend:async value=>{if(!/^\d{1,20}$/.test(value.discordID))throw new Error('Choose a Discord friend.');doc().hiddenFriends ||= [];doc().hiddenFriends=doc().hiddenFriends.filter(id=>id!==value.discordID);if(value.hidden)doc().hiddenFriends.push(value.discordID);await save();await audience();return refresh();},
  assignFriend:async value=>{if(!/^\d{1,20}$/.test(value.discordID))throw new Error('Choose a Discord friend.');if(value.avatarID){const a=doc().avatars.find(a=>a.id===value.avatarID);if(!a)throw new Error('Choose a saved Mii.');doc().friendAssignments[value.discordID]=a;}else delete doc().friendAssignments[value.discordID];await save();return refresh();},
  characters:async value=>{if(value.action==='remove'){if(doc().avatars.length===1)throw new Error('Keep at least one Mii.');doc().avatars=doc().avatars.filter(a=>a.id!==value.id);if(doc().avatar.id===value.id)doc().avatar=doc().avatars[0];}else if(value.action==='primary'){const a=doc().avatars.find(a=>a.id===value.id);if(!a)throw new Error('Choose a saved Mii.');doc().avatar=a;}else throw new Error('Unknown Mii action.');await save();await publishProfile();broadcast();return publicState();},
  appIcon:async id=>{const entry=store.apps.find(a=>a.id===id);if(!entry)throw new Error('Choose an app.');const picked=await dialog.showOpenDialog(BrowserWindow.getFocusedWindow()||window,{filters:[{name:'App icon',extensions:['png','jpg','jpeg','ico']}],properties:['openFile']});if(picked.canceled)return publicState();const file=picked.filePaths[0];if((await fs.stat(file)).size>4*1024*1024)throw new Error('Choose an icon smaller than 4 MB.');const image=nativeImage.createFromPath(file);if(image.isEmpty())throw new Error('Choose a readable image.');entry.icon=image.resize({width:128,height:128,quality:'best'}).toDataURL();await save();broadcast();return publicState();},
  installedApps:async()=>{installed=await applications.installed(app);const result=[];for(const entry of installed){let icon='';if(!entry.steamAppID)try{icon=(await app.getFileIcon(entry.path,{size:'large'})).toDataURL();}catch{}result.push({...entry,icon});}return result;},
  addApp:async value=>{
    store.apps ||= [];if(store.apps.length>=120)throw new Error('The app library is full.');let entry;
    if(value?.id)entry=installed.find(a=>a.id===value.id);else{const picked=await dialog.showOpenDialog(BrowserWindow.getFocusedWindow()||window,{filters:[{name:'Windows application',extensions:['exe','lnk']}],properties:['openFile']});if(picked.canceled)return publicState();entry=applications.item(path.basename(picked.filePaths[0],path.extname(picked.filePaths[0])),picked.filePaths[0]);}
    if(!entry)throw new Error('Choose an installed app.');if(store.apps.some(a=>a.path.toLowerCase()===entry.path.toLowerCase()))return publicState();
    let icon='';if(!entry.steamAppID)try{icon=(await app.getFileIcon(entry.path,{size:'large'})).toDataURL();}catch{}
    store.apps.push({...entry,icon});await save();broadcast();return publicState();
  },
  app:async value=>{store.apps ||= [];const entry=store.apps.find(a=>a.id===value.id);if(!entry)throw new Error('App shortcut unavailable.');if(value.action==='remove')store.apps=store.apps.filter(a=>a.id!==entry.id);else if(value.action==='rename')entry.label=String(value.label||'').trim().slice(0,60)||entry.label;else if(value.action==='launch'){
      if(entry.steamAppID)await shell.openExternal('steam://rungameid/'+Number(entry.steamAppID));else{const error=await shell.openPath(entry.path);if(error)throw new Error('The app could not be opened. Locate it again in Change Apps.');}
      store.history ||= [];store.history=store.history.filter(h=>h.id!==entry.id&&Date.now()-h.at<90*86400000).slice(0,59);store.history.unshift({id:entry.id,at:Date.now()});store.activeApplication={name:entry.label,bundleID:entry.bundleID};await engine.call('cheer',{index:store.apps.indexOf(entry)});
    }else if(value.action==='move'){const index=store.apps.indexOf(entry);store.apps.splice(index,1);store.apps.splice(Math.min(store.apps.length,Math.max(0,value.index|0)),0,entry);}else throw new Error('Unknown app action.');await save();broadcast();return publicState();},
  resources:async()=>({resource:await fs.readFile(path.join(resourceDirectory(),'FFLResHigh.dat')).then(b=>b.toString('base64')).catch(()=>null),body:await fs.readFile(path.join(resourceDirectory(),'body.json')).then(b=>b.toString('base64')).catch(()=>null),wasm:(await fs.readFile(path.join(__dirname,'ffl/vendor/ffl-emscripten.wasm'))).toString('base64')}),
  importResource:async kind=>{if(!['ffl','body'].includes(kind))throw new Error('Unknown resource.');const picked=await dialog.showOpenDialog(BrowserWindow.getFocusedWindow()||window,{title:kind==='ffl'?'Import FFLResHigh.dat':'Import Men2.pack',properties:['openFile']});if(picked.canceled)return null;const file=picked.filePaths[0],stat=await fs.stat(file);if(!stat.isFile()||stat.size<1024||stat.size>(kind==='ffl'?64:128)*1024*1024)throw new Error('Resource is outside its size limit.');const data=await fs.readFile(file);if(kind==='ffl'&&data.subarray(0,4).toString()!=='FFRA')throw new Error('Choose an uncompressed FFL resource with an FFRA header.');const token=cryptoUUID();resourceImports.clear();resourceImports.set(token,{kind,data});return{kind,token,data:data.toString('base64')};},
  commitResource:async value=>{const pending=resourceImports.get(value.token);if(!pending)throw new Error('Resource import expired.');if(pending.kind==='ffl')await atomic(path.join(resourceDirectory(),'FFLResHigh.dat'),pending.data);else{if(typeof value.converted!=='string'||value.converted.length>64*1024*1024)throw new Error('Invalid converted body resource.');const parsed=JSON.parse(value.converted);if(parsed.version!==1||parsed.models?.length!==2||!Array.isArray(parsed.animations)||parsed.animations.length>256)throw new Error('Invalid converted body resource.');await atomic(path.join(resourceDirectory(),'body.json'),value.converted);}resourceImports.delete(value.token);broadcast();return{};},
  removeResource:async kind=>{if(!['ffl','body'].includes(kind))throw new Error('Unknown resource.');await fs.rm(path.join(resourceDirectory(),kind==='ffl'?'FFLResHigh.dat':'body.json'),{force:true});return{};},
  exportMiiBinary:async value=>{const encoded=await engine.call('encodeMii',{avatar:value||doc().avatar});const picked=await dialog.showSaveDialog(BrowserWindow.getFocusedWindow()||window,{defaultPath:'Plaza-Mii.mii',filters:[{name:'Wii U / 3DS Mii',extensions:['mii','ffsd']}]});if(!picked.canceled)await fs.writeFile(picked.filePath,Buffer.from(encoded.data,'base64'));return{};},
  exportPortrait:async value=>{if(typeof value!=='string'||!value.startsWith('data:image/png;base64,')||value.length>20_000_000)throw new Error('Invalid portrait.');const picked=await dialog.showSaveDialog(BrowserWindow.getFocusedWindow()||window,{defaultPath:'Plaza-Mii.png',filters:[{name:'PNG image',extensions:['png']}]});if(!picked.canceled)await fs.writeFile(picked.filePath,Buffer.from(value.split(',')[1],'base64'));return{};},
  activity:async()=>{try{return await request('GET','/v1/notes/activity');}catch(error){if(error.status===404)return{activities:[],unreadCount:0};throw error;}},
  activityRead:async ids=>request('PUT','/v1/notes/activity/read',{ids}),
  musicImport:async kind=>{if(!['plaza','maker','friends','settings','writing'].includes(kind))throw new Error('Unknown soundtrack.');const picked=await dialog.showOpenDialog(BrowserWindow.getFocusedWindow()||window,{filters:[{name:'Music',extensions:['wav','mp3','m4a','ogg']}],properties:['openFile']});if(picked.canceled)return null;const file=picked.filePaths[0],stat=await fs.stat(file);if(!stat.isFile()||stat.size<1||stat.size>256*1024*1024||!/^\.(wav|mp3|m4a|ogg)$/i.test(path.extname(file)))throw new Error('Choose a playable recording up to 256 MB.');const token=cryptoUUID(),target=path.join(root(),'Music/.preview',token+path.extname(file).toLowerCase());await fs.mkdir(path.dirname(target),{recursive:true});await fs.copyFile(file,target);musicImports.set(token,{file:target,name:path.basename(file),kind});return{token,url:'plaza-media://preview/'+token,name:path.basename(file)};},
  discardMusic:async token=>{const pending=musicImports.get(token);if(pending)await fs.rm(pending.file,{force:true});musicImports.delete(token);return{};},
  commitMusic:async token=>{const pending=musicImports.get(token);if(!pending)throw new Error('Music selection expired.');const target=path.join(root(),'Music',token+path.extname(pending.file));await fs.rename(pending.file,target);store.music ||= {};const previous=store.music[pending.kind];store.music[pending.kind]={file:target,name:pending.name};try{await save();}catch(error){if(previous)store.music[pending.kind]=previous;else delete store.music[pending.kind];await fs.rm(target,{force:true});throw error;}musicImports.delete(token);if(previous)await fs.rm(previous.file,{force:true}).catch(()=>{});broadcast();return publicState();},
  exportPlaza:async()=>{const document=await engine.call('portable',{document:portable.exportDocument(doc(),store.apps||[])});const picked=await dialog.showSaveDialog(BrowserWindow.getFocusedWindow()||window,{defaultPath:'My-Plaza.json',filters:[{name:'Portable Plaza',extensions:['json']}]});if(!picked.canceled)await fs.writeFile(picked.filePath,JSON.stringify(document,null,2));return{};},
  importPlaza:async()=>{const picked=await dialog.showOpenDialog(BrowserWindow.getFocusedWindow()||window,{filters:[{name:'Portable Plaza',extensions:['json']}],properties:['openFile']});if(picked.canceled)return publicState();const file=picked.filePaths[0];if((await fs.stat(file)).size>12000000)throw new Error('Plaza files must be smaller than 12 MB.');const document=await engine.call('portable',{document:JSON.parse(await fs.readFile(file,'utf8'))});const choice=await dialog.showMessageBox(BrowserWindow.getFocusedWindow()||window,{type:'question',buttons:['Import Plaza','Cancel'],defaultId:1,cancelId:1,message:`Import ${document.avatars.length} Miis and ${document.notes.length} local notes?`,detail:'This replaces this account’s local Miis, private notes and settings. Shared server notes are preserved. Reconnect Windows app shortcuts in Change Apps.'});if(choice.response!==0)return publicState();const next=portable.importDocument(document,doc());await preserveRecovery();store.accounts[key()]=next;store.apps=document.apps.map(a=>({...a,path:a.steamAppID?'steam://rungameid/'+a.steamAppID:'',icon:''}));await save();await publishProfile();broadcast();return publicState();},
  recoverBackup:async()=>{const value=JSON.parse(await fs.readFile(filename()+'.backup','utf8'));if(!value.accounts?.offline)throw new Error('No readable backup is available.');for(const document of Object.values(value.accounts)){core.validateAvatar(document.avatar);for(const n of document.privateNotes||[])core.validateNote(n);}await preserveRecovery();store=value;store.settings ||= {};store.apps ||= [];doc();await save();broadcast();return publicState();},
  musicRole:async kind=>{if(!['plaza','maker','friends','settings','writing'].includes(kind))throw new Error('Unknown music role.');window.webContents.send('plaza-music-role',kind);return{};},
  musicInfo:async()=>Object.fromEntries(Object.entries(store.music||{}).map(([kind,item])=>[kind,{name:item.name,url:'plaza-media://music/'+kind}])),
  musicReset:async kind=>{delete(store.music||{})[kind];await save();return publicState();},
  notify:async value=>{if(doc().settings.notifications&&Notification.isSupported())new Notification({title:'Plaza activity',body:doc().settings.privatePresentation?'You have new Plaza activity.':String(value||'A friend interacted with your note.').slice(0,160)}).show();return{};}
});
async function preserveRecovery(){if(recoveryRequired){await fs.copyFile(filename(),filename()+'.unreadable-'+Date.now()).catch(()=>{});recoveryRequired=false;}}
async function openPanel(value){const kind=typeof value==='string'?value:value?.kind,context=typeof value==='object'?value.context||{}:{};if(JSON.stringify(context).length>2000)throw new Error('Panel request is too large.');panelContexts.set(kind,context);if(!['maker','friends','settings','composer','activity','journal','apps'].includes(kind))throw new Error('Unknown panel.');if(panels.has(kind)){panels.get(kind).show();panels.get(kind).focus();panels.get(kind).webContents.send('plaza-panel-context',context);return;}const panel=new BrowserWindow({width:kind==='maker'?1000:850,height:kind==='maker'?840:740,minWidth:700,minHeight:560,title:kind==='maker'?'Mii Maker':'Plaza',backgroundColor:'#f5f7f2',webPreferences:{preload:path.join(__dirname,'preload.cjs'),contextIsolation:true,sandbox:true,nodeIntegration:false,autoplayPolicy:'no-user-gesture-required'}});windows.add(panel);panels.set(kind,panel);secure(panel);panel.on('closed',()=>{windows.delete(panel);panels.delete(kind);panelContexts.delete(kind);window.webContents.send('plaza-music-role','plaza');});await panel.loadFile(path.join(__dirname,'index.html'),{query:{panel:kind}});}
function secure(item){item.webContents.setWindowOpenHandler(()=>({action:'deny'}));item.webContents.on('will-navigate',event=>event.preventDefault());item.webContents.session.setPermissionRequestHandler((_contents,_permission,callback)=>callback(false));}
function validID(id) { if (typeof id !== 'string' || !/^[\da-f]{8}-(?:[\da-f]{4}-){3}[\da-f]{12}$/i.test(id)) throw new Error('Invalid note identity.'); return id; }
app.whenReady().then(async () => {
  app.setAppUserModelId('org.squidproductions.plaza.windows');
  try { store = JSON.parse(await fs.readFile(filename(), 'utf8')); if (!store.accounts.offline) throw new Error('Invalid saved plaza.'); }
  catch (error) {
    if (error.code !== 'ENOENT') {
      recoveryRequired=true;
    }
    store = { origin: core.DEFAULT_SERVICE, accounts: { offline: core.document() } };if(!recoveryRequired)await save();
  }
  try { session = JSON.parse(safeStorage.decryptString(await fs.readFile(path.join(root(), 'session.bin')))); core.endpoint(session.origin); validID(session.accountID); }
  catch { session = null; }
  store.settings ||= {};store.apps ||= [];doc();
  await fs.rm(path.join(root(),'Music/.preview'),{recursive:true,force:true});engine=new Engine(app.isPackaged);
  if(process.platform==='win32')native=require(app.isPackaged?path.join(process.resourcesPath,'native/plaza_native.node'):path.join(__dirname,'../native/runtime/plaza_native.node'));
  protocol.handle('plaza-media',async request=>{const url=new URL(request.url),kind=url.pathname.slice(1),item=url.hostname==='preview'?musicImports.get(kind):url.hostname==='music'?store.music?.[kind]:null;if(!item)return new Response('Unavailable',{status:404});const stat=await fs.stat(item.file).catch(()=>null);if(!stat?.isFile()||stat.size<1||stat.size>256*1024*1024)return new Response('Unavailable',{status:404});let start=0,end=stat.size-1,status=200;const range=request.headers.get('range');if(range){const match=/^bytes=(\d*)-(\d*)$/.exec(range);if(!match||!match[1]&&!match[2])return new Response(null,{status:416,headers:{'Content-Range':'bytes */'+stat.size}});if(!match[1])start=Math.max(0,stat.size-Number(match[2]));else{start=Number(match[1]);if(match[2])end=Math.min(end,Number(match[2]));}if(start>end||start>=stat.size)return new Response(null,{status:416,headers:{'Content-Range':'bytes */'+stat.size}});status=206;}const headers={'Content-Type':{'.wav':'audio/wav','.mp3':'audio/mpeg','.m4a':'audio/mp4','.ogg':'audio/ogg'}[path.extname(item.file)]||'application/octet-stream','Content-Length':String(end-start+1),'Accept-Ranges':'bytes'};if(status===206)headers['Content-Range']=`bytes ${start}-${end}/${stat.size}`;return new Response(request.method==='HEAD'?null:require('node:stream').Readable.toWeb(require('node:fs').createReadStream(item.file,{start,end})),{status,headers});});
  ipcMain.handle('plaza', (event, action, value) => {
    const source=BrowserWindow.fromWebContents(event.sender);
    if (!windows.has(source) || event.senderFrame !== source.webContents.mainFrame || !Object.hasOwn(actions, action)) throw new Error('Unsupported request.');
    const next = operation.then(async () => {
      try { if(recoveryRequired&&!['state','resources','engine','recoverBackup','importPlaza','musicInfo','website'].includes(action))throw new Error('Restore a backup or import a plaza in Preferences. The unreadable save is preserved.');return { ok: true, value: await actions[action](value) }; }
      catch (error) { return { ok: false, error: error.message }; }
    });
    operation = next.catch(() => {}); return next;
  });
  ipcMain.handle('plaza-frame',(event,args)=>{if(event.sender!==window.webContents||event.senderFrame!==window.webContents.mainFrame)throw new Error('Unknown scene.');return engine.call('frame',args);});
  window = new BrowserWindow({ width: 1240, height: 850, minWidth: 1060, minHeight: 720, title: 'Plaza', backgroundColor: '#f5f7f2',
    webPreferences: { preload: path.join(__dirname, 'preload.cjs'), contextIsolation: true, sandbox: true, nodeIntegration: false,autoplayPolicy:'no-user-gesture-required' } });
  windows.add(window);secure(window);
  wallpaper=new Wallpaper(window,native,{settings:store.settings,save,notify:message=>window.webContents.send('plaza-error',message),panel:openPanel,quit:()=>app.quit()});
  Menu.setApplicationMenu(Menu.buildFromTemplate([{ label: 'Plaza', submenu: [{ label: 'Downloads & updates', click: actions.website }, { role: 'quit' }] },
    { label: 'Edit', submenu: [{ role: 'undo' }, { role: 'redo' }, { type: 'separator' }, { role: 'cut' }, { role: 'copy' }, { role: 'paste' }, { role: 'selectAll' }] },
    { label: 'View', submenu: [{ role: 'resetZoom' }, { role: 'zoomIn' }, { role: 'zoomOut' }, { role: 'togglefullscreen' }] }]));
  window.on('close',event=>{if(process.platform==='win32'&&!quitting){event.preventDefault();window.hide();}});
  await window.loadFile(path.join(__dirname, 'index.html'));
  if(process.platform==='win32'&&(app.commandLine.hasSwitch('wallpaper')||store.settings.wallpaperAtLogin||store.settings.wallpaper))try{await wallpaper.attach();}catch(error){window.webContents.send('plaza-error',error.message);}
  let lastObservedApp='';const sendEnvironment=()=>{let observed={otherAudio:false,covered:false};try{if(native)observed=JSON.parse(native.environment());}catch{}if(observed.otherAudio)lastAudio=Date.now();const foreground=String(observed.foreground||'').toLowerCase(),entry=(store.apps||[]).find(a=>a.executable&&a.executable.toLowerCase()===foreground||a.directory&&foreground.startsWith(a.directory.toLowerCase()+path.sep));store.activeApplication=entry?{name:entry.label,bundleID:entry.bundleID}:null;if(entry&&entry.id!==lastObservedApp){lastObservedApp=entry.id;store.history ||= [];store.history=store.history.filter(h=>h.id!==entry.id&&Date.now()-h.at<90*86400000).slice(0,59);store.history.unshift({id:entry.id,at:Date.now()});operation=operation.then(save).catch(()=>{});}const visibleWindow=[...windows].some(w=>!w.isDestroyed()&&w.isVisible()&&!w.isMinimized()),ownFullscreen=[...panels.values()].some(w=>w.isFullScreen());const value={locked,suspended,wallpaper:wallpaper.active,moving:!locked&&!suspended&&!window.isMinimized()&&(wallpaper.active?!observed.covered&&!ownFullscreen:window.isVisible()),muteMusic:locked||suspended||(!wallpaper.active&&!visibleWindow)||Date.now()-lastAudio<1500||(wallpaper.active&&observed.covered)};for(const item of windows)if(!item.isDestroyed())item.webContents.send('plaza-environment',value);};
  let lastAudio=0;setInterval(sendEnvironment,500).unref();
  for(const [event,key,value]of[['lock-screen','locked',true],['unlock-screen','locked',false],['suspend','suspended',true],['resume','suspended',false]])powerMonitor.on(event,()=>{if(key==='locked')locked=value;else suspended=value;sendEnvironment();});
  if(native)setInterval(()=>{try{native.pumpDiscord();}catch{}},100).unref();
  let refreshing=false,lastState='';
  function backgroundRefresh(){if(refreshing||!session||locked||suspended)return;refreshing=true;const next=operation.then(()=>sync()).then(value=>{for(const item of windows)if(!item.isDestroyed())item.webContents.send('plaza-snapshot',value);}).catch(error=>{for(const item of windows)if(!item.isDestroyed())item.webContents.send('plaza-error',error.message);}).finally(()=>refreshing=false);operation=next;}
  setInterval(backgroundRefresh,15000).unref();
  if(native)setInterval(()=>{if(!session?.discordSDK)return;try{const current=JSON.parse(native.discordSnapshot()).state;if(current!==lastState){lastState=current;if(current==='ready')backgroundRefresh();}}catch{}},1000).unref();
}).catch(error=>{console.error('Plaza startup failed:',error);dialog.showErrorBox('Plaza could not start',error.message);app.exit(1);});
app.on('before-quit',()=>{quitting=true;wallpaper?.cleanup();native?.disconnectDiscord();engine?.close();});
app.on('window-all-closed',()=>{if(process.platform!=='win32')app.quit();});
