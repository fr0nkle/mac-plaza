const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const core=require('../src/core.cjs'),portable=require('../src/portable.cjs');
test('Miiverse draft visibility survives portable export and retains the legacy friends-only default',()=>{
  const doc=core.document();doc.avatars=[doc.avatar];doc.draft.visibility='private';doc.draft.text='Keep private';
  const value=portable.exportDocument(doc,[]);assert.equal(value.draft.shared,false);
  assert.equal(portable.importDocument(value,doc).draft.visibility,'private');
  delete value.draft.shared;delete value.draft.audience;assert.equal(portable.importDocument(value,doc).draft.visibility,'friends');
});
test('portable Mac documents omit local app paths and convert Foundation dates in both directions',()=>{
  const created=Math.floor(Date.now()/1000),doc=core.document();doc.avatars=[doc.avatar];doc.settings={population:160,rotateHome:true};doc.privateNotes=[{id:randomUUID(),author:doc.avatar,text:'Private',drawing:[],drawingDescription:'',created:created}];doc.remoteNotes=[{text:'Remote friend note'}];
  const value=portable.exportDocument(doc,[{id:randomUUID(),label:'Steam',bundleID:'com.valvesoftware.steam',path:'C:/private/Steam.exe',bookmark:'private'}]);
  assert.equal(value.apps[0].path,undefined);assert.equal(value.apps[0].bookmark,undefined);assert.equal(value.notes.length,1);assert.equal(value.notes[0].shared,false);assert.equal(value.notes[0].created,created-978307200);
  const restored=portable.importDocument(value,doc);assert.equal(restored.privateNotes[0].created,created);assert.deepEqual(restored.remoteNotes,doc.remoteNotes);assert.equal(restored.settings.rotateHome,true);
});

test('private replies and portable app communities survive a Mac document round trip',()=>{const doc=core.document(),id=randomUUID(),replyID=randomUUID();doc.avatars=[doc.avatar];doc.privateNotes=[{id:randomUUID(),author:doc.avatar,text:'Private',drawing:[],drawingDescription:'',created:1900000000,topic:{steamAppID:620,bundleID:'steam.app.620',label:'Portal'},replies:[{id:replyID,author:doc.avatar,text:'Local reply',created:1900000001}]}];const exported=portable.exportDocument(doc,[{id,label:'Portal',bundleID:'steam.app.620',steamAppID:620}]);assert.equal(exported.notes[0].appID,id);const imported=portable.importDocument(exported,doc);assert.equal(imported.privateNotes[0].topic.steamAppID,620);assert.equal(imported.privateNotes[0].replies[0].id,replyID);assert.equal(imported.privateNotes[0].replies[0].created,1900000001);});
test('portable export retains owned public/friends/pending posts and private drafts without exporting received discussions',()=>{
 const doc=core.document(),owner=randomUUID(),other=randomUUID(),now=Date.now()/1000;doc.avatars=[doc.avatar];const n=(text,audience)=>({id:randomUUID(),sourceID:randomUUID(),ownerID:owner,author:doc.avatar,text,drawing:[],drawingDescription:'',created:now,audience,replies:[{id:randomUUID(),ownerID:other,author:doc.avatar,text:'Received reply',created:now}]});
 const publicNote=n('Public','public'),friends=n('Friends','friends');doc.remoteNotes=[publicNote,friends,{...n('Received','public'),ownerID:other}];doc.pending[publicNote.sourceID]={...publicNote,id:publicNote.sourceID,text:'Edited public'};doc.draft={text:'Draft',visibility:'friends',authorID:doc.avatar.id,topic:{steamAppID:620,label:'Portal',bundleID:'steam.app.620'}};
 const exported=portable.exportDocument(doc,[{id:'game',label:'Portal',bundleID:'steam.app.620',steamAppID:620}],owner);assert.deepEqual(exported.notes.map(n=>n.text),['Edited public','Friends']);assert.deepEqual(exported.notes.map(n=>n.audience),['public','friends']);assert.equal(exported.notes[0].replies.length,0);assert.equal(exported.draft.appID,'game');
 const restored=portable.importDocument(exported,doc,owner);assert.equal(restored.privateNotes.length,0);assert.equal(restored.pending[publicNote.sourceID].audience,'public');assert.equal(restored.pending[friends.sourceID].audience,'friends');assert.equal(restored.draft.topic.steamAppID,620);assert.equal(restored.draft.authorID,doc.avatar.id);
});
test('legacy shared imports stay friends-only, private changes retract matching shared IDs, expired notes are pruned',()=>{
 const doc=core.document();doc.avatars=[doc.avatar];doc.privateNotes=[{id:randomUUID(),author:doc.avatar,text:'Private',drawing:[],drawingDescription:'',created:Date.now()/1000}];const value=portable.exportDocument(doc,[]);value.notes[0].shared=true;delete value.notes[0].audience;
 assert.equal(portable.importDocument(value,doc).pending[value.notes[0].id].audience,'friends');value.notes[0].shared=false;assert.equal(portable.importDocument(value,doc,randomUUID()).pending[value.notes[0].id],null);value.notes[0].created=0;assert.equal(portable.importDocument(value,doc).privateNotes.length,0);
});
test('local discussion on a shared owned note survives portable export separately from shared service replies',()=>{
 const doc=core.document(),owner=randomUUID(),id=randomUUID(),now=Date.now()/1000;doc.avatars=[doc.avatar];doc.remoteNotes=[{id:randomUUID(),sourceID:id,ownerID:owner,author:doc.avatar,text:'Shared',drawing:[],drawingDescription:'',created:now,audience:'public',replies:[{id:randomUUID(),ownerID:randomUUID(),author:doc.avatar,text:'Service-owned reply',created:now}]}];doc.ownedMeta={[id]:{created:now,liked:true,replies:[{id:randomUUID(),author:doc.avatar,text:'Original local reply',created:now}]}};
 const exported=portable.exportDocument(doc,[],owner);assert.deepEqual(exported.notes[0].replies.map(r=>r.text),['Original local reply']);assert.equal(exported.notes[0].acknowledged,true);const imported=portable.importDocument(exported,core.document(),owner);assert.equal(imported.ownedMeta[id].replies[0].text,'Original local reply');
});

test('Mac-compatible custom shortcut icons survive export without app paths or bookmarks',()=>{const doc=core.document();doc.avatars=[doc.avatar];const value=portable.exportDocument(doc,[{id:randomUUID(),label:'Custom app',bundleID:'custom.app',path:'C:/private',bookmark:'private',icon:'data:image/png;base64,aGVsbG8='}]);assert.equal(value.apps[0].customIcon,'aGVsbG8=');assert.equal(value.apps[0].path,undefined);assert.equal(value.apps[0].bookmark,undefined);});
