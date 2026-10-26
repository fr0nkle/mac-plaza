'use strict';
const { app, BrowserWindow, ipcMain, shell, safeStorage, dialog, Menu, powerMonitor, Notification, protocol, net, nativeImage, clipboard, utilityProcess, screen } = require('electron');
const fs = require('node:fs/promises');
const path = require('node:path');
const { randomBytes, createHash } = require('node:crypto');
const core = require('./core.cjs');
const {ServiceClient}=require('./service-client.cjs');
const serviceClient=new ServiceClient((...args)=>globalThis.fetch(...args));
const miiverseWindow=require('./miiverse-window.cjs');
const birthday=require('./birthday.cjs');
let birthdayReceipt,birthdayOverlay,birthdayBusy=false,presentation={visible:false,sheet:true,preview:false,reducedMotion:false};
const {Engine}=require('./engine.cjs');
const {Wallpaper}=require('./wallpaper.cjs');
const {FriendRoster,validateFriends,recipients,publicMiis}=require('./social.cjs');
const localSocial=require('./local-social.cjs');
const publicConfig=require('./public-config.json');
const resourcePack=require('./resource-pack.cjs'),{activityCursor}=require('./catalog.cjs'),diagnosticArchive=require('./archive.cjs');
function musicLibrary(){return require('./music-library.cjs').load(app.isPackaged?path.join(process.resourcesPath,'native/Audio'):path.join(__dirname,'../native/runtime/Audio'),store.music||{});}
let updater;
const packs=new Map();let lastDiagnostics=null,interruptedSession=false;const failures=[];
const applications=require('./apps.cjs');
const portable=require('./portable.cjs');
const steam=require('./steam.cjs');
const steamDetails=new Map(),steamRetry=new Map();
const {pathToFileURL}=require('node:url');
let monitor,monitorPath,monitorStarted=0,monitorLast=0,monitorRetry=0,observedEnvironment={otherMusic:false,covered:false};
let engine,native,wallpaper,quitting=false,locked=false,suspended=false,roster=new FriendRoster(),sdk={state:'disconnected',friends:[]},games={},sdkToken='',installed=[],lastSDKRefresh=0,recoveryRequired=false;
const undoLayouts=[],restoredGameScopes=new Set();
function rememberApps(){undoLayouts.push(structuredClone(store.apps||[]));if(undoLayouts.length>20)undoLayouts.shift();}
function homeCatalog(){const unique=new Map();for(const entry of [...(store.apps||[]),...installed])if(!unique.has(entry.bundleID))unique.set(entry.bundleID,entry);return [...unique.values()];}
const windows=new Set(),panels=new Map(),panelContexts=new Map(),resourceImports=new Map(),musicImports=new Map();
protocol.registerSchemesAsPrivileged([{scheme:'plaza-media',privileges:{standard:true,secure:true,supportFetchAPI:true,stream:true}}]);
let window, store, session = null, login = null, localDiscord = null, serviceOnline = false, directAuthBusy = false;
let operation = Promise.resolve();
let activityAlert=null;
let lastAudienceSignature='',lastAudienceAt=0,lastActivityAt=0;
const root = () => app.getPath('userData');
const filename = () => path.join(root(), 'plaza.json');
async function atomic(file, data) {
  await fs.mkdir(path.dirname(file), { recursive: true });
  await fs.writeFile(file + '.tmp', data, { mode: 0o600 });
  await fs.rename(file + '.tmp', file);
}
async function save() {if(recoveryRequired)throw new Error('Restore a backup or import a plaza before saving changes.');core.pruneNotes(store);const previous=await fs.readFile(filename()).catch(()=>null);if(previous){try{const parsed=JSON.parse(previous);core.validateStore(parsed);await atomic(filename()+'.backup',previous);}catch{}}await atomic(filename(), JSON.stringify(store)); }
function key() { return session ? `${session.origin}/${session.accountID}` : 'offline'; }
function doc() { const value=store.accounts[key()] ||= core.document();value.avatars ||= [value.avatar];value.friendAssignments ||= {};value.settings ||= {};value.settings.ambientSound ??= true;return value; }
function publicState() { return { unreadCount:doc().activityCache?.unreadCount||0,activityAlert:activityAlert?.scope===key()?activityAlert.entry:null,connected: !!session, serviceOnline, pendingInteractions: doc().outbox?.length||0, hasLocalDiscord:!!localDiscord, discordApplicationID:localDiscord?.applicationID||session?.discordSDK?.applicationID||store.discordApplicationID||publicConfig.discordApplicationID||'',recoveryRequired, origin: session?.origin || store.origin, document: {...doc(),remoteNotes:localSocial.displayNotes(doc(),session?.accountID)}, version: app.getVersion(),updates:updater?.state(),interruptedSession,monitor:{ready:!!monitorLast&&Date.now()-monitorLast<3000},panels:[...panels.keys()], settings:store.settings||{}, apps:store.apps||[],homeCatalog:homeCatalog(),history:store.history||[],music:musicLibrary(),wallpaper:wallpaper?.state()||{supported:process.platform==='win32',active:false,interactive:true}, discord:{state:sdk.state,count:sdk.friends.length},accountID:session?.accountID }; }
function broadcast(){for(const item of windows)if(!item.isDestroyed())item.webContents.send('plaza-state',publicState());}
async function directAuthorization(applicationID,previous){
  if(!native?.authorizeLocal)throw Error('Direct Discord sign-in needs the Windows native bridge.');
  if(directAuthBusy)throw Error('Finish the pending Discord sign-in first.');
  if(typeof applicationID!=='string'||!/^\d{1,20}$/.test(applicationID)||BigInt(applicationID)===0n||BigInt(applicationID)>=2n**64n)throw Error('Enter a valid Discord Application ID.');
  directAuthBusy=true;
  try{
    native.authorizeLocal({applicationID,discordID:previous?.discordID||session?.discordSDK?.discordID||'',refreshToken:previous?.refreshToken||''});
    const end=Date.now()+180000;
    while(Date.now()<end){
      native.pumpDiscord();const value=native.authorizationResult();
      if(value){const result=JSON.parse(value);if(result.error)throw Error(result.error);
        if(result.applicationID!==applicationID||!/^\d{1,20}$/.test(result.discordID)||typeof result.accessToken!=='string'||typeof result.refreshToken!=='string'||result.accessToken.length>4096||result.refreshToken.length>4096||!Number.isFinite(result.expiresAt)||result.expiresAt<=Date.now()/1000)throw Error('Invalid direct Discord credentials.');
        if(session?.discordSDK?.discordID&&session.discordSDK.discordID!==result.discordID)throw Error('Connect the same Discord account used for sharing.');
        if(!safeStorage.isEncryptionAvailable())throw Error('Windows credential encryption is unavailable.');
        await atomic(path.join(root(),'discord-local.bin'),safeStorage.encryptString(JSON.stringify(result)));localDiscord=result;store.discordApplicationID=applicationID;await save();return result;
      }
      await new Promise(resolve=>setTimeout(resolve,100));
    }
    throw Error('Discord sign-in timed out. Try again.');
  }finally{native.cancelAuthorization();directAuthBusy=false;}
}
async function ensureSDK(){
  let credentials=localDiscord||session?.discordSDK;
  if(!native||!credentials){sdk={state:session?'authorization-required':'disconnected',friends:[]};return;}
  if(credentials.expiresAt<Date.now()/1000+90){
    try{if(credentials.localAuthorization)credentials=await directAuthorization(credentials.applicationID,credentials);
    else{credentials=await request('POST','/v1/discord/refresh',{refreshToken:credentials.refreshToken});session.discordSDK=credentials;await persistSession();}}
    catch{native.disconnectDiscord();sdkToken='';sdk={state:'authorization-required',friends:[]};return;}
  }
  if(sdkToken!==credentials.accessToken){native.configureDiscord(credentials);sdkToken=credentials.accessToken;roster.reset();}
  sdk=validateFriends(JSON.parse(native.discordSnapshot()));
}
async function attachDirectSession(){
  if(session||!localDiscord||localDiscord.expiresAt<Date.now()/1000+90)return;
  try{
    const auth={origin:core.endpoint(store.origin),...(await request('POST','/v1/auth/direct',{accessToken:localDiscord.accessToken},{origin:store.origin})),discordSDK:localDiscord};
    const snapshot=await request('GET','/v1/snapshot',undefined,auth);validID(snapshot.account.id);auth.accountID=snapshot.account.id;session=auth;
    if(!store.accounts[key()])store.accounts[key()]=core.document();
    doc().cachedSnapshot=snapshot;await persistSession();await save();
  }catch{serviceOnline=false;}
}
async function flushInteractions(){
  if(!session)return;localSocial.prune(doc());
  for(const item of [...(doc().outbox||[])]){
    try{
      const route='/v1/notes/'+validID(item.noteID)+(Object.hasOwn(item,'liked')?'/like':'/replies/'+validID(item.replyID));
      await request(item.remove?'DELETE':'PUT',route,Object.hasOwn(item,'liked')?{liked:item.liked}:{author:item.author,text:item.text});
      localSocial.acknowledge(doc(),item,session.accountID,true);await save();
    }catch(error){
      if([400,403,404,409,410,422].includes(error.status)){localSocial.acknowledge(doc(),item,session.accountID,false);await save();for(const item of windows)if(!item.isDestroyed())item.webContents.send('plaza-error','A pending change could not be delivered: '+error.message);}
      else throw error;
    }
  }
}
function localSnapshot(){
  const snapshot=structuredClone(doc().cachedSnapshot||{account:null,friends:[],unlinkedFriends:[],contacts:[],incoming:[],outgoing:[]});
  const threads=localSocial.displayNotes(doc(),session?.accountID);snapshot.friends=publicMiis(snapshot.friends,threads);
  if(sdk.state==='ready'){snapshot.friends=roster.resolve(sdk.friends,{friends:snapshot.friends},doc(),doc().showDiscordGames?games:{},threads);snapshot.unlinkedFriends=[];}
  else if(!serviceOnline){snapshot.friends=[];snapshot.unlinkedFriends=[];}
  return{...publicState(),snapshot,notes:threads};
}
async function queueInteraction(change){
  if(!session)throw Error('Connect to the sharing service once before interacting.');
  const previous=doc().outbox;localSocial.enqueue(doc(),change,session.accountID);
  try{await save();}catch(error){doc().outbox=previous;throw error;}
  broadcast();
  if(serviceOnline){try{await flushInteractions();return await refresh();}catch{serviceOnline=false;games={};}}
  return localSnapshot();
}
async function audience(){
  if(sdk.state!=='ready'||!session||!(doc().shareProfile||(doc().remoteNotes||[]).some(n=>n.ownerID===session.accountID)))return;
  const ids=recipients(sdk.friends,doc().hiddenFriends),signature=JSON.stringify([key(),ids]);
  if(signature===lastAudienceSignature&&Date.now()-lastAudienceAt<300000)return;
  await request('PUT','/v1/discord/recipients',{discordIDs:ids});lastAudienceSignature=signature;lastAudienceAt=Date.now();
}
async function publishProfile(){if(session){doc().profilePending=true;await save();const owned=await request('GET','/v1/notes/owned');if(owned.notes.length)await request('PUT','/v1/notes',{notes:core.mergeNotes(owned.notes,session.accountID,doc().pending),primaryAvatar:core.publicAvatar(doc().avatar)});await request('PUT','/v1/profile',{avatar:core.publicAvatar(doc().avatar),note:doc().profileNote||'',sharing:!!doc().shareProfile,sharePresence:doc().sharePresence!==false,shareActivity:!!doc().shareActivity,shareDiscordFriends:!!doc().shareProfile});doc().profilePending=false;await save();}}
async function persistSession() {
  if (!safeStorage.isEncryptionAvailable()) throw new Error('Windows credential encryption is unavailable. Sign-in was not saved.');
  await atomic(path.join(root(), 'session.bin'), safeStorage.encryptString(JSON.stringify(session)));
}
async function request(method, route, body, auth = session) {
  return serviceClient.request(method,route,body,auth);
}

async function updateGameHistory(snapshot){
  if(sdk.state!=='ready'||!doc().showDiscordGames)return;
  const result=await engine.call('gameHistory',{history:doc().gameHistory||{games:{}},friends:sdk.friends,restore:!restoredGameScopes.has(key()),...(snapshot?{snapshot}:{})});
  restoredGameScopes.add(key());doc().gameHistory=result.history;games={...(snapshot||{}),games:result.games,customStatuses:snapshot?.customStatuses||[]};
}
async function refresh() {
  await ensureSDK();await attachDirectSession();
  if(!session)return localSnapshot();
  try{
    const snapshot=await request('GET','/v1/snapshot');
    const threads=await request('GET','/v1/notes/threads');threads.notes=threads.notes.filter(n=>!core.expired(n));
    doc().cachedSnapshot=snapshot;doc().remoteNotes=threads.notes;localSocial.prune(doc());serviceOnline=true;
    await audience();
    if(sdk.state==='ready'&&doc().showDiscordGames&&Date.now()-lastSDKRefresh>12000){try{const observed=await request('POST','/v1/discord/games',{discordIDs:recipients(sdk.friends,doc().hiddenFriends)});await updateGameHistory(observed);lastSDKRefresh=Date.now();}catch{await updateGameHistory();}}
    try{await request('POST','/v1/heartbeat',{active:!locked&&!suspended,application:doc().shareActivity?store.activeApplication||null:null});}catch{}
    await pollActivity();await save();
  }catch(error){serviceOnline=false;await updateGameHistory().catch(()=>{games={};});if([401,403].includes(error.status)){doc().remoteNotes=[];doc().cachedSnapshot=null;await save();if(error.status===401){session=null;activityAlert=null;app.setBadgeCount(0);await fs.rm(path.join(root(),'session.bin'),{force:true});}}}
  return localSnapshot();
}
async function sync() {
  const initial=await refresh();
  if(!session||!serviceOnline)return initial;
  let changed=false;
  try{
    if(doc().profilePending){await publishProfile();changed=true;}
    if(Object.keys(doc().pending).length){
      const {notes}=await request('GET','/v1/notes/owned');
      await request('PUT','/v1/notes',{notes:core.mergeNotes(notes,session.accountID,doc().pending),primaryAvatar:core.publicAvatar(doc().avatar)});
      doc().pending={};await save();changed=true;
    }
    if(doc().outbox?.length){await flushInteractions();changed=true;}
    if(changed)return refresh();
  }catch{serviceOnline=false;await updateGameHistory().catch(()=>{games={};});return localSnapshot();}
  return initial;
}
const actions = {
  state: async () => localSnapshot(),
  presentation:async value=>{for(const key of ['visible','sheet','preview','reducedMotion'])if(typeof value?.[key]!=='boolean')throw Error('Invalid plaza visibility.');presentation=value;return{};},
  primaryBirthday:async value=>{
    if(!birthday.valid(value?.month,value?.day))throw Error('Choose a valid month and day, or clear both.');
    const primary=doc().avatar.id,month=value.month,day=value.day;
    doc().avatar.features.birthMonth=month;doc().avatar.features.birthDay=day;
    const saved=doc().avatars.find(a=>a.id===primary);if(saved){saved.features.birthMonth=month;saved.features.birthDay=day;}
    await save();broadcast();return publicState();
  },
  refresh: sync,
  blocks: async () => request('GET', '/v1/blocks'),
  draft: async value => {
    if (typeof value.text !== 'string' || value.text.length > 1000 || !Array.isArray(value.drawing) || JSON.stringify(value).length > 2_000_000) throw new Error('Draft is too large.');
    doc().draft = value; await save(); return {};
  },
  profile: async value => {
    // Import appearance only, using the same bounded fields as the Mac service.
    if (JSON.stringify(value).length > 100000) throw new Error('Character file is too large.');const originalID=value.id;value=await engine.call('normalizeAvatar',{avatar:value});value.id=originalID;core.validateAvatar(value);
    if(!doc().avatars.some(a=>a.id===value.id)&&doc().avatars.length>=100)throw new Error('The character library is full. Remove a Mii before adding another.');const primaryChanged=doc().avatar.id===value.id;if(primaryChanged)doc().avatar=value;
    const existing=doc().avatars.findIndex(a=>a.id===value.id);if(existing>=0)doc().avatars[existing]=value;else if(doc().avatars.length<100)doc().avatars.push(value);await save();
    broadcast();try{if(primaryChanged)await publishProfile();}catch(error){for(const item of windows)item.webContents.send('plaza-error','Mii saved locally. '+error.message);}
    return publicState();
  },
  note: async value => {
    value.note={...value.note,id:core.uuidKey(value.note.sourceID||value.note.id)};core.validateNote(value.note);core.validateJournalChange(doc(),session?.accountID,value.note,value.preserveDraft);
    if (core.expired(value.note)) throw new Error('This note has expired. Write a new note to post it again.');
    doc().ownedMeta ||= {};const previousLocal=doc().privateNotes.find(n=>n.id===value.note.id)||doc().ownedMeta[value.note.id],localReplies=previousLocal?.replies||(value.note.replies||[]).filter(r=>!r.ownerID);
    if (!['private', 'friends', 'public'].includes(value.visibility)) throw new Error('Choose a valid post visibility.');
    if (value.visibility !== 'private') {
      if (!session) throw new Error('Connect Discord before sharing a post.');
      doc().ownedMeta[value.note.id]={replies:structuredClone(localReplies),liked:!!previousLocal?.liked,created:value.note.created};
      doc().pending[value.note.id] = {...value.note, audience: value.visibility, author: structuredClone(doc().avatar)};
      doc().privateNotes = doc().privateNotes.filter(n => n.id !== value.note.id);
    } else {
      if (!doc().privateNotes.some(n => n.id === value.note.id) && doc().privateNotes.length >= 200) throw new Error('You have reached the private post limit.');
      const previous=doc().privateNotes.find(n=>n.id===value.note.id);doc().privateNotes = doc().privateNotes.filter(n => n.id !== value.note.id).concat({...value.note,replies:localReplies,liked:previousLocal?.liked??false});
      delete doc().ownedMeta[value.note.id];if (session) doc().pending[value.note.id] = null;
    }
    if(!value.preserveDraft)doc().draft = { text: '', drawing: [], drawingDescription: '', visibility: 'public' }; await save();
    return sync();
  },
  noteRead:async id=>{validID(id);const note=doc().remoteNotes?.find(n=>n.id===id||n.sourceID===id),sourceID=note?.sourceID||id;doc().readNotes=[...new Set([...(doc().readNotes||[]),sourceID])].slice(-1000);for(const n of doc().privateNotes)if(n.id===id)n.read=true;await save();return publicState();},
  deleteNote: async id => {
    if(doc().ownedMeta)delete doc().ownedMeta[id];
    doc().privateNotes = doc().privateNotes.filter(n => n.id !== id);
    if (session) doc().pending[id] = null;
    await save(); return sync();
  },
  localLike:async id=>{const note=doc().privateNotes.find(n=>n.id===id);if(!note)throw Error('Private note is unavailable.');note.liked=!note.liked;await save();return publicState();},
  localReply:async value=>{const note=doc().privateNotes.find(n=>n.id===value.noteID)||doc().ownedMeta?.[value.noteID];if(!note)throw Error('Local note is unavailable.');note.replies ||= [];if(value.remove)note.replies=note.replies.filter(r=>r.id!==value.id);else{if(typeof value.text!=='string'||![...value.text.trim()].length||[...value.text.trim()].length>280)throw Error('Write a reply up to 280 characters.');const old=note.replies.find(r=>r.id===value.id);if(old)old.text=value.text.trim();else{if(note.replies.length>=50||[...doc().privateNotes,...Object.values(doc().ownedMeta||{})].reduce((n,x)=>n+(x.replies?.length||0),0)>=2000)throw Error('This note has reached its reply limit.');note.replies.push({id:validID(value.id),author:structuredClone(doc().avatar),text:value.text.trim(),created:Date.now()/1000});}}await save();return publicState();},
  invite: async () => request('POST', '/v1/invites', {}),
  friend: async value => {
    if (!['request', 'accept', 'remove', 'block', 'unblock'].includes(value.action)) throw new Error('Unknown friend action.');
    await request('POST', '/v1/friends/' + value.action, value.action === 'request' ? { code: value.code } : { id: value.id });
    return refresh();
  },
  like: async value => queueInteraction({noteID:validID(value.id),liked:!!value.liked}),
  reply: async value => queueInteraction({noteID:validID(value.noteID),replyID:validID(value.id),remove:!!value.remove,
    author:doc().avatar,text:value.text,displayName:doc().cachedSnapshot?.account?.displayName}),
  authLocal:async applicationID=>{await directAuthorization(applicationID);await ensureSDK();await attachDirectSession();const value=await refresh();broadcast();return value;},
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
    if(localDiscord&&localDiscord.discordID!==auth.discordSDK?.discordID){localDiscord=null;await fs.rm(path.join(root(),'discord-local.bin'),{force:true});}
    session = auth; login = null;lastActivityAt=0;lastAudienceSignature='';
    if (!store.accounts[key()]) {
      store.accounts[key()] = core.document();
      if (snapshot.account.avatar) doc().avatar = snapshot.account.avatar;
      else doc().avatar = structuredClone(store.accounts.offline.avatar);
      doc().shareProfile=!!snapshot.account.shareDiscordFriends;
      doc().avatars=[doc().avatar];
    }
    await persistSession(); await save();const value=await refresh();broadcast();return value;
  },
  logout: async () => {
    // Revoke if reachable; always remove this device's encrypted credential.
    try { if (session) await request('POST', '/v1/logout', {}); } catch { /* local disconnect still works offline */ }
    native?.disconnectDiscord();sdkToken='';sdk={state:'disconnected',friends:[]};roster.reset();games={};
    session = null; login = null; localDiscord=null;serviceOnline=false;activityAlert=null;app.setBadgeCount(0);lastActivityAt=0;lastAudienceSignature='';await fs.rm(path.join(root(),'discord-local.bin'),{force:true});await fs.rm(path.join(root(), 'session.bin'), { force: true });
    broadcast();return publicState();
  },
  newMii:async()=>engine.call('newAvatar'),
  importMii: async () => {
    const result = await dialog.showOpenDialog(BrowserWindow.getFocusedWindow()||window, { filters: [{ name: 'Mii or character JSON', extensions: ['json','mii','ffsd'] }], properties: ['openFile'] });
    if (result.canceled) return null;
    const file = result.filePaths[0];
    if ((await fs.stat(file)).size >= 100000) throw new Error('Character file is too large.');
    const value = path.extname(file).toLowerCase()==='.json'?JSON.parse(await fs.readFile(file,'utf8')):await engine.call('decodeMii',{data:(await fs.readFile(file)).toString('base64')});value.id=cryptoUUID();
    const normalized=await engine.call('normalizeAvatar',{avatar:value});normalized.id=value.id;return normalized;
  },
  exportMii: async value => {
    core.validateAvatar(value||doc().avatar);
    const result = await dialog.showSaveDialog(window, { defaultPath: 'Plaza-Mii.json', filters: [{ name: 'Character JSON', extensions: ['json'] }] });
    if (!result.canceled) await fs.writeFile(result.filePath, JSON.stringify(value||doc().avatar, null, 2));
    return {};
  },
  copyInvite:async value=>{if(typeof value!=='string'||value.length>80)throw new Error('Invalid invitation.');clipboard.writeText(value);return{};},
  updateCheck:async()=>{updater.check(!!store.settings.automaticUpdateDownloads);return publicState();},
  updateDownload:async()=>{updater.download();return publicState();},
  updateInstall:async()=>{await updater.install();setImmediate(()=>app.quit());return{};},
  updatePreferences:async value=>{for(const key of ['automaticUpdateChecks','automaticUpdateDownloads'])if(Object.hasOwn(value,key)){if(typeof value[key]!=='boolean')throw Error('Invalid update preference.');store.settings[key]=value[key];}await save();broadcast();return publicState();},
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
    const allowed=['population','pauseMotion','pausePosts','privatePresentation','safeMode','largerText','ambientSound','musicVolume','makerMusicVolume','friendsMusicVolume','settingsMusicVolume','writingMusicVolume','miiverseMusicVolume','miiverseAlternateTheme','uiSoundVolume','uiSoundEffects','rotateHome','notifications'];
    for(const [key,val]of Object.entries(value)){if(!allowed.includes(key))continue;if(key==='population'){if(!Number.isInteger(val)||val<20||val>200)throw new Error('Choose 20–200 Miis.');}else if(key.endsWith('Volume')){if(!Number.isFinite(val)||val<0||val>(key==='uiSoundVolume'?1:.35))throw new Error('Invalid volume.');}else if(typeof val!=='boolean')throw new Error('Invalid setting.');doc().settings[key]=val;}
    await save();broadcast();return publicState();
  },
  loginSettings:async value=>{store.settings ||= {};store.settings.openAtLogin=!!value.openAtLogin;store.settings.wallpaperAtLogin=!!value.wallpaperAtLogin;app.setLoginItemSettings({openAtLogin:store.settings.openAtLogin,path:process.execPath,args:store.settings.wallpaperAtLogin?['--wallpaper']:[]});await save();return publicState();},
  sharing:async value=>{doc().shareProfile=!!value.shareProfile;doc().sharePresence=!!value.sharePresence;doc().shareActivity=!!value.shareActivity;doc().showDiscordGames=!!value.showDiscordGames;if(!doc().showDiscordGames){games={};lastSDKRefresh=0;}doc().profileNote=String(value.note||'').slice(0,280);await save();try{await publishProfile();await audience();}catch{serviceOnline=false;}return refresh();},
  hideFriend:async value=>{if(!/^\d{1,20}$/.test(value.discordID))throw new Error('Choose a Discord friend.');doc().hiddenFriends ||= [];doc().hiddenFriends=doc().hiddenFriends.filter(id=>id!==value.discordID);if(value.hidden)doc().hiddenFriends.push(value.discordID);await save();await audience();return refresh();},
  assignFriend:async value=>{if(!/^\d{1,20}$/.test(value.discordID))throw new Error('Choose a Discord friend.');if(value.avatarID){const a=doc().avatars.find(a=>a.id===value.avatarID);if(!a)throw new Error('Choose a saved Mii.');doc().friendAssignments[value.discordID]=a;}else delete doc().friendAssignments[value.discordID];await save();return refresh();},
  characters:async value=>{if(value.action==='remove'){if(doc().avatars.length===1)throw new Error('Keep at least one Mii.');doc().avatars=doc().avatars.filter(a=>a.id!==value.id);if(doc().avatar.id===value.id)doc().avatar=doc().avatars[0];}else if(value.action==='primary'){const a=doc().avatars.find(a=>a.id===value.id);if(!a)throw new Error('Choose a saved Mii.');doc().avatar=a;}else throw new Error('Unknown Mii action.');await save();await publishProfile();broadcast();return publicState();},
  appIcon:async id=>{const entry=store.apps.find(a=>a.id===id);if(!entry)throw new Error('Choose an app.');const picked=await dialog.showOpenDialog(BrowserWindow.getFocusedWindow()||window,{filters:[{name:'App icon',extensions:['png','jpg','jpeg','ico']}],properties:['openFile']});if(picked.canceled)return publicState();const file=picked.filePaths[0];if((await fs.stat(file)).size>4*1024*1024)throw new Error('Choose an icon smaller than 4 MB.');const image=nativeImage.createFromPath(file);if(image.isEmpty())throw new Error('Choose a readable image.');rememberApps();entry.icon=image.resize({width:128,height:128,quality:'best'}).toDataURL();entry.customIcon=entry.icon.split(',')[1];await save();broadcast();return publicState();},
  resetApps:async()=>{rememberApps();store.apps.sort((a,b)=>a.label.localeCompare(b.label,undefined,{numeric:true,sensitivity:'base'}));await save();broadcast();return publicState();},
  installedApps:async()=>{if(!installed.length)installed=await applications.installed(app);const result=[];for(const entry of installed){let icon='';if(!entry.steamAppID)try{icon=(await app.getFileIcon(entry.executable||entry.path,{size:'large'})).toDataURL();}catch{}result.push({...entry,icon});}return result;},
  addApp:async value=>{
    store.apps ||= [];if(store.apps.length>=120)throw new Error('The app library is full.');let entry;
    if(value?.id)entry=installed.find(a=>a.id===value.id);else{const picked=await dialog.showOpenDialog(BrowserWindow.getFocusedWindow()||window,{filters:[{name:'Windows application',extensions:['exe','lnk']}],properties:['openFile']});if(picked.canceled)return publicState();entry=applications.item(path.basename(picked.filePaths[0],path.extname(picked.filePaths[0])),picked.filePaths[0]);}
    if(!entry)throw new Error('Choose an installed app.');if(store.apps.some(a=>a.path.toLowerCase()===entry.path.toLowerCase()))return publicState();
    let icon='';if(!entry.steamAppID)try{icon=(await app.getFileIcon(entry.executable||entry.path,{size:'large'})).toDataURL();}catch{}
    rememberApps();store.apps.push({...entry,icon});await save();broadcast();return publicState();
  },
  app:async value=>{store.apps ||= [];const entry=homeCatalog().find(a=>a.id===value.id);if(!entry)throw new Error('App shortcut unavailable.');if(value.action!=='launch'){if(!store.apps.some(a=>a.id===value.id))throw new Error('Pin this app before editing it.');rememberApps();}if(value.action==='remove')store.apps=store.apps.filter(a=>a.id!==entry.id);else if(value.action==='rename')entry.label=String(value.label||'').trim().slice(0,60)||entry.label;else if(value.action==='launch'){
      if(!entry.path&&!entry.steamAppID)throw new Error('Locate this app in Shortcut settings.');if(entry.steamAppID)await shell.openExternal('steam://rungameid/'+Number(entry.steamAppID));else{const error=await shell.openPath(entry.path);if(error)throw new Error('The app could not be opened. Locate it again in Change Apps.');}
      store.history ||= [];store.history=store.history.filter(h=>h.id!==entry.id&&Date.now()-h.at<90*86400000).slice(0,59);store.history.unshift({id:entry.id,at:Date.now()});store.activeApplication={name:entry.label,bundleID:entry.bundleID};await engine.call('cheer',{index:Number.isInteger(value.islandIndex)?value.islandIndex:store.apps.indexOf(entry)});
    }else if(value.action==='move'){const index=store.apps.indexOf(entry);store.apps.splice(index,1);store.apps.splice(Math.min(store.apps.length,Math.max(0,value.index|0)),0,entry);}else throw new Error('Unknown app action.');await save();broadcast();return publicState();},
  appIconImage:async id=>{const entry=homeCatalog().find(a=>a.id===id);if(!entry)return'';if(entry.icon)return entry.icon;if(entry.steamAppID){try{const bytes=await applications.steamArtwork(entry);if(bytes){const image=nativeImage.createFromBuffer(bytes);if(!image.isEmpty())entry.icon=image.resize({width:128}).toDataURL();}}catch{}}else if(entry.path)try{entry.icon=(await app.getFileIcon(entry.executable||entry.path,{size:'large'})).toDataURL();}catch{}return entry.icon||'';},
  locateApp:async id=>{const entry=store.apps.find(a=>a.id===id);if(!entry)throw new Error('Choose a saved app.');const picked=await dialog.showOpenDialog(BrowserWindow.getFocusedWindow()||window,{title:'Locate '+entry.label,filters:[{name:'Windows application',extensions:['exe','lnk']}],properties:['openFile']});if(picked.canceled)return publicState();rememberApps();entry.path=picked.filePaths[0];entry.executable=/\.exe$/i.test(entry.path)?entry.path:'';if(!entry.executable)try{entry.executable=shell.readShortcutLink(entry.path).target;}catch{}try{entry.icon=(await app.getFileIcon(entry.executable||entry.path,{size:'large'})).toDataURL();}catch{}await save();broadcast();return publicState();},
  appDetails:async id=>{
    const entry=homeCatalog().find(a=>a.id===id);if(!entry)throw new Error('Choose an app.');if(!entry.steamAppID)return{};const appID=Number(entry.steamAppID);if(!Number.isInteger(appID)||appID<1||appID>4294967295)throw new Error('Invalid Steam game.');
    const file=path.join(root(),'SteamPreviews',appID+'.json');let value=steamDetails.get(appID);if(!value){try{if((await fs.stat(file)).size<3_000_000)value=JSON.parse(await fs.readFile(file,'utf8'));}catch{}if(value?.appID!==appID)value={appID};steamDetails.set(appID,value);}
    if(value.fetchedAt>Date.now()-7*86400000&&value.summary&&value.artwork||steamRetry.get(appID)>Date.now())return value;steamRetry.set(appID,Date.now()+60000);
    try{const detail=steam.metadata(await steam.download('https://store.steampowered.com/api/appdetails?appids='+appID+'&l=english&filters=basic',1_000_000),appID);if(detail.summary)value.summary=detail.summary;if(!value.artwork&&detail.imageURL){const bytes=await steam.download(detail.imageURL,5_000_000),image=nativeImage.createFromBuffer(bytes),size=image.getSize();if(!image.isEmpty()&&size.width<=8192&&size.height<=8192&&size.width*size.height<=16_000_000){const scaled=image.resize({width:Math.min(920,size.width)});const jpeg=scaled.toJPEG(86);if(jpeg.length<=2_000_000)value.artwork='data:image/jpeg;base64,'+jpeg.toString('base64');}}value.fetchedAt=Date.now();await atomic(file,JSON.stringify(value));}catch{}return value;
  },
  undoApps:async()=>{if(undoLayouts.length){store.apps=undoLayouts.pop();await save();broadcast();}return publicState();},
  exportDrawing:async value=>{if(typeof value!=='string'||!value.startsWith('data:image/png;base64,')||value.length>2_800_000)throw new Error('Drawing exceeds the export limit.');const data=Buffer.from(value.split(',')[1],'base64');if(data.length>2_000_000)throw new Error('Drawing exceeds the export limit.');const picked=await dialog.showSaveDialog(BrowserWindow.getFocusedWindow()||window,{defaultPath:'Plaza-Drawing.png',filters:[{name:'PNG drawing',extensions:['png']}]});if(!picked.canceled)await fs.writeFile(picked.filePath,data);return{};},
  resources:async()=>({resource:await fs.readFile(path.join(resourceDirectory(),'FFLResHigh.dat')).then(b=>b.toString('base64')).catch(()=>null),body:await fs.readFile(path.join(resourceDirectory(),'body.json')).then(b=>b.toString('base64')).catch(()=>null),wasm:(await fs.readFile(path.join(__dirname,'ffl/vendor/ffl-emscripten.wasm'))).toString('base64')}),
  importResource:async kind=>{if(!['ffl','body'].includes(kind))throw new Error('Unknown resource.');const picked=await dialog.showOpenDialog(BrowserWindow.getFocusedWindow()||window,{title:kind==='ffl'?'Import FFLResHigh.dat':'Import Men2.pack',properties:['openFile']});if(picked.canceled)return null;const file=picked.filePaths[0],stat=await fs.stat(file);if(!stat.isFile()||stat.size<1024||stat.size>(kind==='ffl'?64:128)*1024*1024)throw new Error('Resource is outside its size limit.');const data=await fs.readFile(file);if(kind==='ffl'&&data.subarray(0,4).toString()!=='FFRA')throw new Error('Choose an uncompressed FFL resource with an FFRA header.');const token=cryptoUUID();resourceImports.clear();resourceImports.set(token,{kind,data});return{kind,token,data:data.toString('base64')};},
  commitResource:async value=>{const pending=resourceImports.get(value.token);if(!pending)throw new Error('Resource import expired.');if(pending.kind==='ffl')await atomic(path.join(resourceDirectory(),'FFLResHigh.dat'),pending.data);else{if(typeof value.converted!=='string'||value.converted.length>64*1024*1024)throw new Error('Invalid converted body resource.');const parsed=JSON.parse(value.converted);if(parsed.version!==1||parsed.models?.length!==2||!Array.isArray(parsed.animations)||parsed.animations.length>256)throw new Error('Invalid converted body resource.');await atomic(path.join(resourceDirectory(),'body.json'),value.converted);}resourceImports.delete(value.token);broadcast();return{};},
  removeResource:async kind=>{if(!['ffl','body'].includes(kind))throw new Error('Unknown resource.');await fs.rm(path.join(resourceDirectory(),kind==='ffl'?'FFLResHigh.dat':'body.json'),{force:true});return{};},
  exportMiiBinary:async value=>{const encoded=await engine.call('encodeMii',{avatar:value||doc().avatar});const picked=await dialog.showSaveDialog(BrowserWindow.getFocusedWindow()||window,{defaultPath:'Plaza-Mii.mii',filters:[{name:'Wii U / 3DS Mii',extensions:['mii','ffsd']}]});if(!picked.canceled)await fs.writeFile(picked.filePath,Buffer.from(encoded.data,'base64'));return{};},
  exportPortrait:async value=>{if(doc().settings.safeMode)throw Error('Turn off safe mode to export a 3D portrait.');if(typeof value!=='string'||!value.startsWith('data:image/png;base64,')||value.length>20_000_000)throw new Error('Invalid portrait.');const picked=await dialog.showSaveDialog(BrowserWindow.getFocusedWindow()||window,{defaultPath:'Plaza-Mii.png',filters:[{name:'PNG image',extensions:['png']}]});if(!picked.canceled)await fs.writeFile(picked.filePath,Buffer.from(value.split(',')[1],'base64'));return{};},
  activity:async()=>{
    if(doc().activityCache&&Date.now()-lastActivityAt<10000)return doc().activityCache;
    try{const value=await request('GET','/v1/notes/activity');const read=new Set(doc().pendingActivityRead||[]);value.activities=(value.activities||[]).map(entry=>({...entry,read:entry.read||read.has(entry.id)}));value.unreadCount=value.activities.filter(e=>!e.read).length;doc().activityCache=value;lastActivityAt=Date.now();await save();return value;}
    catch{return doc().activityCache||{activities:[],unreadCount:0};}
  },
  activityOpen:async id=>{
    const entry=(doc().activityCache?.activities||[]).find(e=>e.id===id);if(!entry)throw Error('This activity is no longer available.');
    await actions.activityRead([entry.id]);await openPanel({kind:'miiverse',context:{noteID:entry.noteID}});return publicState();
  },
  dismissActivity:async()=>{activityAlert=null;broadcast();return{};},
  activityRead:async ids=>{
    if(!Array.isArray(ids)||ids.length>200||ids.some(id=>!Number.isSafeInteger(id)||id<=0))throw Error('Invalid activity identity.');
    const visible=new Set((doc().activityCache?.activities||[]).map(e=>e.id));doc().pendingActivityRead=[...new Set([...(doc().pendingActivityRead||[]),...ids.filter(id=>visible.has(id))])].slice(-200);
    if(doc().activityCache){doc().activityCache.activities=doc().activityCache.activities.map(e=>({...e,read:e.read||ids.includes(e.id)}));doc().activityCache.unreadCount=doc().activityCache.activities.filter(e=>!e.read).length;}
    await save();app.setBadgeCount(doc().activityCache?.unreadCount||0);if(activityAlert&&!doc().activityCache?.activities?.some(e=>e.id===activityAlert.entry.id&&!e.read))activityAlert=null;broadcast();return doc().activityCache||{activities:[],unreadCount:0};
  },
  musicImport:async kind=>{if(!['plaza','maker','friends','settings','writing','miiverse','miiverseAlternate','uiClick','uiBack'].includes(kind))throw new Error('Unknown soundtrack.');const picked=await dialog.showOpenDialog(BrowserWindow.getFocusedWindow()||window,{filters:[{name:'Music',extensions:['wav','mp3','m4a','ogg','aac','aif','aiff','caf','flac']}],properties:['openFile']});if(picked.canceled)return null;const file=picked.filePaths[0],stat=await fs.stat(file);if(!stat.isFile()||stat.size<1||stat.size>256*1024*1024||!/^\.(wav|mp3|m4a|ogg|aac|aif|aiff|caf|flac)$/i.test(path.extname(file)))throw new Error('Choose a playable recording up to 256 MB.');const token=cryptoUUID(),target=path.join(root(),'Music/.preview',token+path.extname(file).toLowerCase());await fs.mkdir(path.dirname(target),{recursive:true});await fs.copyFile(file,target);musicImports.set(token,{file:target,name:path.basename(file),kind});return{token,url:'plaza-media://preview/'+token,name:path.basename(file)};},
  discardMusic:async token=>{const pending=musicImports.get(token);if(pending)await fs.rm(pending.file,{force:true});musicImports.delete(token);return{};},
  commitMusic:async token=>{const pending=musicImports.get(token);if(!pending)throw new Error('Music selection expired.');const target=path.join(root(),'Music',token+path.extname(pending.file));await fs.rename(pending.file,target);store.music ||= {};const previous=store.music[pending.kind];store.music[pending.kind]={file:target,name:pending.name};try{await save();}catch(error){if(previous)store.music[pending.kind]=previous;else delete store.music[pending.kind];await fs.rm(target,{force:true});throw error;}musicImports.delete(token);if(previous)await fs.rm(previous.file,{force:true}).catch(()=>{});broadcast();return publicState();},
  exportPlaza:async()=>{const document=await engine.call('portable',{document:portable.exportDocument(doc(),store.apps||[],session?.accountID)});const picked=await dialog.showSaveDialog(BrowserWindow.getFocusedWindow()||window,{defaultPath:'My-Plaza.json',filters:[{name:'Portable Plaza',extensions:['json']}]});if(!picked.canceled)await fs.writeFile(picked.filePath,JSON.stringify(document,null,2));return{};},
  importPlaza:async()=>{const picked=await dialog.showOpenDialog(BrowserWindow.getFocusedWindow()||window,{filters:[{name:'Portable Plaza',extensions:['json']}],properties:['openFile']});if(picked.canceled)return publicState();const file=picked.filePaths[0];if((await fs.stat(file)).size>12000000)throw new Error('Plaza files must be smaller than 12 MB.');const document=await engine.call('portable',{document:JSON.parse(await fs.readFile(file,'utf8'))});const choice=await dialog.showMessageBox(BrowserWindow.getFocusedWindow()||window,{type:'question',buttons:['Import Plaza','Cancel'],defaultId:1,cancelId:1,message:`Import ${document.avatars.length} Miis and ${document.notes.length} local notes?`,detail:'This replaces this account’s local Miis, private notes and settings. Imported shared posts retain their audience and queue for this account; existing server posts are preserved. Reconnect Windows app shortcuts in Change Apps.'});if(choice.response!==0)return publicState();const next=portable.importDocument(document,doc(),session?.accountID);await preserveRecovery();store.accounts[key()]=next;store.apps=document.apps.map(a=>({...a,path:a.steamAppID?'steam://rungameid/'+a.steamAppID:'',icon:a.customIcon?nativeImage.createFromBuffer(Buffer.from(a.customIcon,'base64')).resize({width:128,height:128}).toDataURL():''}));await save();await publishProfile();broadcast();return publicState();},
  recoverBackup:async()=>{const value=JSON.parse(await fs.readFile(filename()+'.backup','utf8'));core.validateStore(value);await preserveRecovery();core.migrateAudiences(value);core.normalizeNoteIDs(value);store=value;store.settings ||= {};store.apps ||= [];doc();await save();broadcast();return publicState();},
  musicPreview:async value=>{window.webContents.send('plaza-music-preview',!!value);return{};},
  musicRole:async kind=>{if(!['plaza','maker','friends','settings','writing','miiverse','miiverseAlternate','uiClick','uiBack'].includes(kind))throw new Error('Unknown music role.');window.webContents.send('plaza-music-role',kind);return{};},
  musicInfo:async()=>Object.fromEntries(Object.entries(musicLibrary()).map(([kind,item])=>[kind,{name:item.name,url:'plaza-media://music/'+kind}])),
  musicReset:async kind=>{if(!['plaza','maker','friends','settings','writing','miiverse','miiverseAlternate','uiClick','uiBack'].includes(kind))throw new Error('Unknown soundtrack.');const previous=store.music?.[kind];delete(store.music||{})[kind];try{await save();}catch(error){if(previous)store.music[kind]=previous;throw error;}if(previous)await fs.rm(previous.file,{force:true}).catch(()=>{});broadcast();return publicState();},
  notify:async value=>{if(doc().settings.notifications&&Notification.isSupported())new Notification({title:'Plaza activity',body:doc().settings.privatePresentation?'You have new Plaza activity.':String(value||'A friend interacted with your note.').slice(0,160)}).show();return{};}
});
async function pollActivity(){
  if(!session)return;if(doc().pendingActivityRead?.length){const ids=[...doc().pendingActivityRead];try{await request('PUT','/v1/notes/activity/read',{ids});doc().pendingActivityRead=doc().pendingActivityRead.filter(id=>!ids.includes(id));await save();}catch{}}let value;try{value=await actions.activity();}catch{return;}store.activityCursors ||= {};const scope=key(),next=activityCursor(store.activityCursors[scope],value.activities||[]);store.activityCursors[scope]=next.cursor;
  app.setBadgeCount(value.unreadCount||0);if(activityAlert&&(activityAlert.scope!==scope||!value.activities.some(e=>e.id===activityAlert.entry.id&&!e.read)))activityAlert=null;if(next.fresh.length)activityAlert={scope,entry:next.fresh.sort((a,b)=>b.id-a.id)[0]};if(next.fresh.length&&doc().settings.notifications&&Notification.isSupported()){const latest=next.fresh.sort((a,b)=>b.id-a.id)[0],notice=new Notification({title:'Plaza activity',body:doc().settings.privatePresentation?'You have new Plaza activity.':(latest.actorName||'A friend')+(latest.kind==='like'?' liked your note.':' replied to your note.')});notice.on('click',()=>{if(key()===scope)operation=operation.then(()=>actions.activityOpen(latest.id)).catch(()=>{});});notice.show();}
}
Object.assign(actions,{
  preparePack:async()=>{const picked=await dialog.showOpenDialog(BrowserWindow.getFocusedWindow()||window,{filters:[{name:'Plaza Resource Pack',extensions:['plazapack']}],properties:['openFile']});if(picked.canceled)return null;for(const pack of packs.values())await fs.rm(pack.folder,{recursive:true,force:true});packs.clear();const pack=await resourcePack.prepare(picked.filePaths[0]),token=cryptoUUID();packs.set(token,pack);const resources=await actions.resources();return{token,name:pack.manifest.name,animationCount:pack.animationCount,resources:{...resources,resource:(await fs.readFile(path.join(pack.folder,'FFLResHigh.dat'))).toString('base64'),body:(await fs.readFile(path.join(pack.folder,'plaza-body.json'))).toString('base64')},music:pack.manifest.entries.filter(e=>e.kind==='music').map(e=>({name:e.name,url:'plaza-media://pack/'+token+'/'+e.file}))};},
  commitPack:async token=>{const pack=packs.get(token);if(!pack)throw Error('Resource pack selection expired.');try{const result=await resourcePack.install(pack,root(),store,save);broadcast();return result;}finally{await fs.rm(pack.folder,{recursive:true,force:true});packs.delete(token);}},
  discardPack:async token=>{const pack=packs.get(token);if(pack)await fs.rm(pack.folder,{recursive:true,force:true});packs.delete(token);return{};},
  dismissDiagnostics:async()=>{interruptedSession=false;return{};},
  exportDiagnostics:async notes=>{if(typeof notes!=='string'||notes.length>10000)throw Error('Keep the description under 10,000 characters.');const picked=await dialog.showSaveDialog(BrowserWindow.getFocusedWindow()||window,{defaultPath:'Plaza-Diagnostics.zip',filters:[{name:'Diagnostics ZIP',extensions:['zip']}]});if(picked.canceled)return{};const info={app:'Plaza',version:app.getVersion(),platform:process.platform,architecture:process.arch,os:require('node:os').release(),electron:process.versions.electron,recoveryRequired,interruptedSession,rendererMode:doc().settings.safeMode?'safe':'3D',nativeRuntimeLoaded:!!native,failures,windowsCrashReports:await require('./diagnostics.cjs').crashReports(process.platform==='win32'?process.env.LOCALAPPDATA:null)};await fs.writeFile(picked.filePath,diagnosticArchive.diagnostics(info,notes,require('node:os').homedir()));lastDiagnostics=picked.filePath;interruptedSession=false;shell.showItemInFolder(lastDiagnostics);return{exported:true};},
  emailDiagnostics:async()=>{if(!lastDiagnostics)throw Error('Export diagnostics first.');const data=await fs.readFile(lastDiagnostics),boundary='Plaza-'+cryptoUUID(),email='To: alexanderhosier@squidproductions.org\r\nSubject: Plaza Windows diagnostics\r\nX-Unsent: 1\r\nMIME-Version: 1.0\r\nContent-Type: multipart/mixed; boundary="'+boundary+'"\r\n\r\n--'+boundary+'\r\nContent-Type: text/plain; charset=utf-8\r\n\r\nPlease review this diagnostic attachment before sending.\r\n--'+boundary+'\r\nContent-Type: application/zip\r\nContent-Disposition: attachment; filename="Plaza-Diagnostics.zip"\r\nContent-Transfer-Encoding: base64\r\n\r\n'+data.toString('base64').match(/.{1,76}/g).join('\r\n')+'\r\n--'+boundary+'--\r\n';const file=path.join(root(),'Diagnostics-Draft.eml');await fs.writeFile(file,email);const error=await shell.openPath(file);if(error){shell.showItemInFolder(file);throw Error('Email draft saved. Open it with your mail app to review and send.');}return{};}
});
async function preserveRecovery(){if(recoveryRequired){await fs.copyFile(filename(),filename()+'.unreadable-'+Date.now()).catch(()=>{});recoveryRequired=false;}}
function restorePanelMusic(preferred){
  const visible=[...panels].filter(([,w])=>!w.isDestroyed()&&w.isVisible()&&!w.isMinimized());
  const chosen=visible.find(([,w])=>w===preferred)||visible.find(([,w])=>w.isFocused())||visible.at(-1),kind=chosen?.[0];
  const role=kind==='miiverse'?'miiverse':kind==='composer'?'writing':['maker','friends','settings'].includes(kind)?kind:'plaza';
  if(window&&!window.isDestroyed())window.webContents.send('plaza-music-role',role);
}
let miiverseSaveTimer;
function rememberMiiverseBounds(){
  const panel=panels.get('miiverse');
  if(!panel||panel.isDestroyed()||panel.isMinimized()||panel.isMaximized()||panel.isFullScreen()||recoveryRequired)return;
  store.miiverseBounds=panel.getBounds();
}
function saveMiiverseBounds(){
  rememberMiiverseBounds();clearTimeout(miiverseSaveTimer);
  miiverseSaveTimer=setTimeout(()=>{if(!quitting&&!recoveryRequired)operation=operation.then(save).catch(()=>{});},250);
  miiverseSaveTimer.unref();
}
async function openPanel(value){
  const kind=typeof value==='string'?value:value?.kind,context=typeof value==='object'?value.context||{}:{};
  if(JSON.stringify(context).length>2000)throw new Error('Panel request is too large.');
  if(!['maker','friends','settings','composer','activity','miiverse','apps'].includes(kind))throw new Error('Unknown panel.');
  panelContexts.set(kind,context);
  if(panels.has(kind)){const panel=panels.get(kind);if(panel.isMinimized())panel.restore();panel.show();panel.focus();panel.webContents.send('plaza-panel-context',context);return;}
  const miiverse=kind==='miiverse';
  const area=miiverseWindow.displayArea(miiverse?store.miiverseBounds:null,screen.getAllDisplays().map(d=>d.workArea),screen.getDisplayMatching(window.getBounds()).workArea);
  const bounds=miiverse?miiverseWindow.fitBounds(store.miiverseBounds,area):{width:kind==='maker'?1000:850,height:kind==='maker'?840:740};
  const panel=new BrowserWindow({...bounds,minWidth:miiverse?Math.min(720,area.width):700,minHeight:miiverse?Math.min(540,area.height):560,
    title:miiverse?'Miiverse':kind==='maker'?'Mii Maker':'Windows Plaza',backgroundColor:'#f5f7f2',
    webPreferences:{preload:path.join(__dirname,'preload.cjs'),contextIsolation:true,sandbox:true,nodeIntegration:false,autoplayPolicy:'no-user-gesture-required'}});
  if(miiverse){const frame=panel.getBounds(),content=panel.getContentBounds(),dw=frame.width-content.width,dh=frame.height-content.height,minimum={minWidth:Math.min(720+dw,area.width),minHeight:Math.min(540+dh,area.height)},anchor=window.getBounds();panel.setMinimumSize(minimum.minWidth,minimum.minHeight);panel.setBounds(miiverseWindow.fitBounds(store.miiverseBounds||{width:1000+dw,height:720+dh,x:anchor.x+(anchor.width-1000-dw)/2,y:anchor.y+(anchor.height-720-dh)/2},area,minimum));}
  panel.on('page-title-updated',event=>event.preventDefault());
  windows.add(panel);panels.set(kind,panel);secure(panel);broadcast();
  const musicRole=()=>restorePanelMusic(panel);
  for(const event of ['focus','show','hide','minimize','restore'])panel.on(event,musicRole);for(const event of ['hide','minimize'])panel.on(event,()=>panel.webContents.send('plaza-stop-preview'));
  if(miiverse){for(const event of ['resize','move'])panel.on(event,saveMiiverseBounds);panel.on('close',()=>{rememberMiiverseBounds();clearTimeout(miiverseSaveTimer);if(!recoveryRequired)operation=operation.then(save).catch(()=>{});});}
  panel.on('closed',()=>{windows.delete(panel);panels.delete(kind);panelContexts.delete(kind);broadcast();if(!window.isDestroyed()){window.webContents.send('plaza-music-preview',false);restorePanelMusic();}});
  await panel.loadFile(path.join(__dirname,'index.html'),{query:{panel:kind}});
}

function birthdayAvailability(){return{loaded:!!store,visible:!!window&&!window.isDestroyed()&&window.isVisible()&&!window.isMinimized()&&presentation.visible,
  recoveryRequired,safeMode:!!doc().settings.safeMode,locked,suspended,sheet:presentation.sheet||panels.size>0,preview:presentation.preview,covered:!!observedEnvironment.covered,celebrating:!!birthdayOverlay?.window};}
function checkBirthday(){
  if(quitting||birthdayBusy||!birthdayReceipt||!birthday.eligible(birthdayAvailability()))return;
  birthdayBusy=true;operation=operation.then(async()=>{if(!birthday.eligible(birthdayAvailability()))return;const primary=structuredClone(doc().avatar);
    if(await birthdayReceipt.claim(primary))await birthdayOverlay.show(primary,screen.getDisplayMatching(window.getBounds()),presentation.reducedMotion||!!doc().settings.pauseMotion);
  }).catch(()=>{}).finally(()=>birthdayBusy=false);
}
function secure(item){item.webContents.setWindowOpenHandler(()=>({action:'deny'}));item.webContents.on('will-navigate',event=>event.preventDefault());item.webContents.session.setPermissionRequestHandler((_contents,_permission,callback)=>callback(false));}
function validID(id) { if (typeof id !== 'string' || !/^[\da-f]{8}-(?:[\da-f]{4}-){3}[\da-f]{12}$/i.test(id)) throw new Error('Invalid note identity.'); return id; }
app.whenReady().then(async () => {
  app.setAppUserModelId('org.squidproductions.plaza.windows');
  try{const events=JSON.parse(await fs.readFile(path.join(root(),'runtime-events.json'),'utf8'));for(const e of events.slice(-10))if(typeof e.time==='string'&&Date.parse(e.time)>Date.now()-30*86400000&&e.kind==='renderer-exit'&&typeof e.reason==='string'&&e.reason.length<80&&Number.isInteger(e.exitCode))failures.push({time:e.time,kind:e.kind,reason:e.reason,exitCode:e.exitCode});}catch{}
  interruptedSession=await fs.stat(path.join(root(),'active-session')).then(()=>true).catch(()=>false);await fs.mkdir(root(),{recursive:true});await fs.writeFile(path.join(root(),'active-session'),'active');
  app.on('render-process-gone',(_event,_contents,details)=>{failures.push({time:new Date().toISOString(),kind:'renderer-exit',reason:details.reason,exitCode:details.exitCode});if(failures.length>10)failures.shift();atomic(path.join(root(),'runtime-events.json'),JSON.stringify(failures)).catch(()=>{});});
  try { store = JSON.parse(await fs.readFile(filename(), 'utf8')); core.validateStore(store); }
  catch (error) {
    if (error.code !== 'ENOENT') {
      recoveryRequired=true;
    }
    store = { audienceVersion: 1, origin: core.DEFAULT_SERVICE, accounts: { offline: core.document() } };if(!recoveryRequired)await save();
  }
  try { session = JSON.parse(safeStorage.decryptString(await fs.readFile(path.join(root(), 'session.bin')))); core.endpoint(session.origin); validID(session.accountID); }
  catch { session = null; }
  try{localDiscord=JSON.parse(safeStorage.decryptString(await fs.readFile(path.join(root(),'discord-local.bin'))));if(localDiscord.localAuthorization!==true||session?.discordSDK?.discordID&&session.discordSDK.discordID!==localDiscord.discordID)localDiscord=null;}catch{localDiscord=null;}
  store.settings ||= {};store.apps ||= [];doc();
  if (!recoveryRequired){const audiences=core.migrateAudiences(store),identities=core.normalizeNoteIDs(store);if(audiences||identities)await save();}
  if (!recoveryRequired && core.pruneNotes(store)) await save();
  const updateDirectory=path.join(root(),'Updates'),installedUpdater=process.platform==='win32'&&app.isPackaged&&require('node:fs').existsSync(path.join(process.resourcesPath,'plaza-installed'));
  updater=new(require('./updates.cjs').Updater)({current:app.getVersion(),directory:updateDirectory,installed:installedUpdater,notify:broadcast,startWorker:async relaunch=>{
    await fs.mkdir(updateDirectory,{recursive:true});
    for(const name of ['updates.cjs','update-worker.cjs'])await fs.copyFile(path.join(__dirname,name),path.join(updateDirectory,name));
    const job={directory:updateDirectory,installDirectory:path.dirname(process.execPath),pid:process.pid,current:app.getVersion(),relaunch};
    const child=require('node:child_process').spawn(process.execPath,[path.join(updateDirectory,'update-worker.cjs'),JSON.stringify(job)],{env:{...process.env,ELECTRON_RUN_AS_NODE:'1'},detached:true,stdio:'ignore',windowsHide:true});
    await new Promise((resolve,reject)=>{child.once('spawn',resolve);child.once('error',reject);});child.unref();
  }});
  await updater.load();
  // Bootstrap precedes windows, the native bridge and engine. Record only updater
  // flags for recovery diagnostics, then exit directly after durable saves and
  // worker handoff; ordinary UI shutdown has no resources to release on this path.
  if(process.platform==='win32'){
    await fs.mkdir(updateDirectory,{recursive:true}).catch(()=>{});
    await fs.writeFile(path.join(updateDirectory,'startup.json'),JSON.stringify({current:app.getVersion(),phase:updater.state().phase,installed:installedUpdater,automatic:!!store.settings.automaticUpdateDownloads,ready:!!updater.ready,autoInstallAllowed:updater.autoInstallAllowed!==false,recoveryRequired})).catch(()=>{});
    if(store.settings.automaticUpdateDownloads&&updater.ready&&updater.autoInstallAllowed!==false&&!recoveryRequired){try{await save();await updater.install();await fs.rm(path.join(root(),'active-session'),{force:true});quitting=true;app.exit(0);return;}catch{updater.set('error','The update could not be installed. Please retry from System Update.');}}
  }

  birthdayReceipt=new birthday.BirthdayReceipt(path.join(root(),'birthday-celebration.json'));birthdayOverlay=new birthday.BirthdayOverlay(BrowserWindow);
  await fs.rm(path.join(root(),'Music/.preview'),{recursive:true,force:true});engine=new Engine(app.isPackaged);
  if(process.platform==='win32'){monitorPath=app.isPackaged?path.join(process.resourcesPath,'native/plaza_native.node'):path.join(__dirname,'../native/runtime/plaza_native.node');native=require(monitorPath);}
  protocol.handle('plaza-media',async request=>{const url=new URL(request.url),kind=url.pathname.slice(1),pieces=kind.split('/'),pack=url.hostname==='pack'?packs.get(pieces[0]):null,entry=pack?.manifest.entries.find(e=>e.file===pieces[1]&&e.kind==='music'),item=url.hostname==='preview'?musicImports.get(kind):url.hostname==='music'?musicLibrary()[kind]:entry?{file:path.join(pack.folder,entry.file)}:null;if(!item)return new Response('Unavailable',{status:404});const stat=await fs.stat(item.file).catch(()=>null);if(!stat?.isFile()||stat.size<1||stat.size>256*1024*1024)return new Response('Unavailable',{status:404});let start=0,end=stat.size-1,status=200;const range=request.headers.get('range');if(range){const match=/^bytes=(\d*)-(\d*)$/.exec(range);if(!match||!match[1]&&!match[2])return new Response(null,{status:416,headers:{'Content-Range':'bytes */'+stat.size}});if(!match[1])start=Math.max(0,stat.size-Number(match[2]));else{start=Number(match[1]);if(match[2])end=Math.min(end,Number(match[2]));}if(start>end||start>=stat.size)return new Response(null,{status:416,headers:{'Content-Range':'bytes */'+stat.size}});status=206;}const headers={'Content-Type':{'.wav':'audio/wav','.mp3':'audio/mpeg','.m4a':'audio/mp4','.ogg':'audio/ogg'}[path.extname(item.file)]||'application/octet-stream','Content-Length':String(end-start+1),'Accept-Ranges':'bytes'};if(status===206)headers['Content-Range']=`bytes ${start}-${end}/${stat.size}`;return new Response(request.method==='HEAD'?null:require('node:stream').Readable.toWeb(require('node:fs').createReadStream(item.file,{start,end})),{status,headers});});
  ipcMain.handle('plaza', (event, action, value) => {
    const source=BrowserWindow.fromWebContents(event.sender);
    if (!windows.has(source) || event.senderFrame !== source.webContents.mainFrame || !Object.hasOwn(actions, action)) throw new Error('Unsupported request.');
    const next = operation.then(async () => {
      try { if(action==='presentation'&&source!==window)throw new Error('Only the plaza reports visibility.'); if(recoveryRequired&&!['state','resources','engine','recoverBackup','importPlaza','musicInfo','website'].includes(action))throw new Error('Restore a backup or import a plaza in Preferences. The unreadable save is preserved.');return { ok: true, value: await actions[action](value) }; }
      catch (error) { return { ok: false, error: error.message }; }
    });
    operation = next.catch(() => {}); return next;
  });
  ipcMain.handle('plaza-frame',(event,args)=>{if(event.sender!==window.webContents||event.senderFrame!==window.webContents.mainFrame)throw new Error('Unknown scene.');return engine.call('frame',args);});
  window = new BrowserWindow({ width: 1240, height: 850, minWidth: 1060, minHeight: 720, title: 'Windows Plaza', backgroundColor: '#f5f7f2',
    webPreferences: { preload: path.join(__dirname, 'preload.cjs'), contextIsolation: true, sandbox: true, nodeIntegration: false,autoplayPolicy:'no-user-gesture-required' } });
  windows.add(window);secure(window);
  wallpaper=new Wallpaper(window,native,{settings:store.settings,save,notify:message=>window.webContents.send('plaza-error',message),panel:openPanel,quit:()=>app.quit()});
  Menu.setApplicationMenu(Menu.buildFromTemplate([{ label: 'Windows Plaza', submenu: [{ label: 'Check for Updates…', click: ()=>updater.check(!!store.settings.automaticUpdateDownloads) }, { label: 'Downloads', click: actions.website }, { role: 'quit' }] },
    { label: 'Edit', submenu: [{ role: 'undo' }, { role: 'redo' }, { type: 'separator' }, { role: 'cut' }, { role: 'copy' }, { role: 'paste' }, { role: 'selectAll' }] },
    { label: 'View', submenu: [{ role: 'resetZoom' }, { role: 'zoomIn' }, { role: 'zoomOut' }, { role: 'togglefullscreen' }] }]));
  window.on('close',event=>{if(process.platform==='win32'&&!quitting){event.preventDefault();window.hide();}});
  await window.loadFile(path.join(__dirname, 'index.html'));
  if(process.platform==='win32'&&(app.commandLine.hasSwitch('wallpaper')||store.settings.wallpaperAtLogin||store.settings.wallpaper))try{await wallpaper.attach();}catch(error){window.webContents.send('plaza-error',error.message);}
  if(process.platform==='win32'&&app.isPackaged){const check=()=>{if(!quitting&&!locked&&!suspended&&store.settings.automaticUpdateChecks!==false)updater.check(!!store.settings.automaticUpdateDownloads);};setTimeout(check,30000).unref();setInterval(check,6*60*60*1000).unref();}
  applications.installed(app).then(value=>{installed=value;broadcast();}).catch(()=>{});
  let lastObservedApp='';const sendEnvironment=()=>{if(quitting)return;if(native){if(monitor&&Date.now()-Math.max(monitorLast,monitorStarted)>5000){monitor.kill();monitor=null;monitorRetry=Date.now()+1000;}if(!monitor&&Date.now()>=monitorRetry)startMonitor();}const observed=Date.now()-monitorLast<3000?observedEnvironment:{otherMusic:false,covered:false};const foreground=String(observed.foreground||'').toLowerCase(),entry=homeCatalog().find(a=>a.executable&&a.executable.toLowerCase()===foreground||a.directory&&foreground.startsWith(a.directory.toLowerCase()+path.sep));store.activeApplication=entry?{name:entry.label,bundleID:entry.bundleID}:null;if(entry&&entry.id!==lastObservedApp){lastObservedApp=entry.id;store.history ||= [];store.history=store.history.filter(h=>h.id!==entry.id&&Date.now()-h.at<90*86400000).slice(0,59);store.history.unshift({id:entry.id,at:Date.now()});operation=operation.then(save).catch(()=>{});}const ownFullscreen=[...panels.values()].some(w=>w.isFullScreen());if((locked||suspended||observed.covered)&&birthdayOverlay?.window)birthdayOverlay.dismiss();const value={locked,suspended,wallpaper:wallpaper.active,moving:!locked&&!suspended&&!window.isMinimized()&&!observed.covered&&(wallpaper.active?!ownFullscreen:window.isVisible()),muteMusic:require('./music-interruption.cjs').muteMusic({locked,suspended,otherMusic:observed.otherMusic})};for(const item of windows)if(!item.isDestroyed())item.webContents.send('plaza-environment',value);};
  function startMonitor(){monitorStarted=Date.now();const child=utilityProcess.fork(path.join(__dirname,'environment.cjs'),[monitorPath,String(process.pid)],{serviceName:'Plaza audio and activity monitor',stdio:'ignore'});monitor=child;child.on('message',value=>{if(monitor!==child||typeof value!=='string'||value.length>65536)return;try{const next=JSON.parse(value);if(typeof next.otherMusic!=='boolean'||typeof next.covered!=='boolean'||typeof next.foreground!=='string')return;observedEnvironment=next;monitorLast=Date.now();}catch{}});child.on('exit',()=>{if(monitor===child){monitor=null;monitorLast=0;monitorRetry=Date.now()+5000;}});}
  setInterval(sendEnvironment,500).unref();setInterval(checkBirthday,1000).unref();
  for(const [event,key,value]of[['lock-screen','locked',true],['unlock-screen','locked',false],['suspend','suspended',true],['resume','suspended',false]])powerMonitor.on(event,()=>{if(key==='locked')locked=value;else suspended=value;sendEnvironment();});
  if(native)setInterval(()=>{try{native.pumpDiscord();}catch{}},100).unref();
  let refreshing=false,lastState='';
  function backgroundRefresh(){if(quitting||refreshing||(!session&&!localDiscord)||locked||suspended)return;refreshing=true;const next=operation.then(()=>sync()).then(value=>{for(const item of windows)if(!item.isDestroyed())item.webContents.send('plaza-snapshot',value);}).catch(error=>{for(const item of windows)if(!item.isDestroyed())item.webContents.send('plaza-error',error.message);}).finally(()=>refreshing=false);operation=next;}
  setInterval(backgroundRefresh,15000).unref();
  setInterval(()=>{operation=operation.then(async()=>{if(!recoveryRequired&&core.pruneNotes(store)){await save();broadcast();}}).catch(()=>{});},60000).unref();
  if(native)setInterval(()=>{if(!session?.discordSDK&&!localDiscord)return;try{const current=JSON.parse(native.discordSnapshot()).state;if(current!==lastState){lastState=current;if(current==='ready')backgroundRefresh();}}catch{}},1000).unref();
}).catch(error=>{console.error('Plaza startup failed:',error);dialog.showErrorBox('Windows Plaza could not start',error.message);app.exit(1);});
app.on('before-quit',event=>{
  if(quitting)return;event.preventDefault();birthdayOverlay?.dismiss();rememberMiiverseBounds();clearTimeout(miiverseSaveTimer);if(store&&!recoveryRequired)operation=operation.then(save).catch(()=>{});quitting=true;monitor?.kill();monitor=null;console.info('Plaza shutdown: beginning');
  // Let pending saves and audio teardown finish before destroying renderers.
  // Deferring quit also lets an inspector-triggered quit return to its caller.
  setImmediate(async()=>{
    const bounded=promise=>Promise.race([promise,new Promise(resolve=>setTimeout(resolve,2000))]);
    try{await bounded(operation);console.info('Plaza shutdown: stopping audio');await bounded(Promise.allSettled([...windows].filter(item=>!item.isDestroyed()).map(item=>item.webContents.executeJavaScript('window.plazaScene?.setMoving(false);window.stopMusicPreview?.();window.PlazaUISounds?.stop();window.PlazaMusic?.shutdown();'))));}catch(error){console.error('Plaza shutdown:',error.message);}
    console.info('Plaza shutdown: releasing desktop');wallpaper?.cleanup();native?.disconnectDiscord();engine?.close();for(const item of windows)if(!item.isDestroyed())item.destroy();console.info('Plaza shutdown: exiting');await fs.rm(path.join(root(),'active-session'),{force:true}).catch(()=>{});for(const pack of packs.values())await fs.rm(pack.folder,{recursive:true,force:true}).catch(()=>{});app.exit(0);
  });
});
app.on('window-all-closed',()=>{if(process.platform!=='win32')app.quit();});

// Main-process access for installed-app integration tests; never exposed over IPC.
module.exports={getUpdater:()=>updater};
