const { test } = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const core = require('../src/core.cjs');
const note = text => ({id:randomUUID(),author:core.avatar(),text,drawing:[],drawingDescription:'',created:Date.now()/1000});
test('HTTPS and local-only development origins',()=>{
  assert.equal(core.endpoint('https://plaza.example/'),'https://plaza.example');
  assert.equal(core.endpoint('http://127.0.0.1:8787'),'http://127.0.0.1:8787');
  for(const value of ['http://example.com','https://user:secret@example.com','https://example.com/path','https://example.com/?token=x','file:///tmp/plaza'])assert.throws(()=>core.endpoint(value));
});
test('only portable Mac-compatible note fields are published',()=>{
  const value=note('Hello Mac');value.author.features.creator='Private';value.author.features.birthMonth=10;value.path='C:\\private';value.bookmark='secret';value.replies=[{text:'Local reply'}];
  const wire=core.wireNote(value);assert.equal(wire.author.features.creator,'');assert.equal(wire.author.features.birthMonth,0);assert.equal(wire.path,undefined);assert.equal(wire.replies,undefined);assert.equal(value.author.features.creator,'Private');
});
test('first sign-in preserves existing account notes, edits and deletions merge by source ID',()=>{
  const own=note('Mac-authored'),other=note('A friend'),owner=randomUUID();
  const remote=[{...own,id:randomUUID(),sourceID:own.id,ownerID:owner},{...other,sourceID:other.id,ownerID:randomUUID()}];
  assert.deepEqual(core.mergeNotes(remote,owner,{}),[core.wireNote(own)]);
  const added=note('Windows-authored');const merged=core.mergeNotes(remote,owner,{[added.id]:added});assert.equal(merged.length,2);
  assert.deepEqual(core.mergeNotes(remote,owner,{[own.id]:null}),[]);
  assert.deepEqual(core.mergeNotes([],owner,{}),[]);
});
test('drawing coordinates, counts and Unicode text are bounded',()=>{
  core.validateNote(note('😀'.repeat(280)));assert.throws(()=>core.validateNote(note('😀'.repeat(281))));
  const n=note('');n.drawing=[{eraser:false,points:[{x:.3,y:.5}]}];n.drawingDescription='A dot';core.validateNote(n);
  n.drawing[0].points[0].x=NaN;assert.throws(()=>core.validateNote(n));
  n.drawing=[{eraser:false,points:[{x:1.1,y:0}]}];assert.throws(()=>core.validateNote(n));
  n.drawing=[{eraser:false,points:Array(20001).fill({x:0,y:0})}];assert.throws(()=>core.validateNote(n));
});
test('shared replacement bounds match Mac service',()=>{
  const pending={};for(let i=0;i<201;i++){const n=note('Hi');pending[n.id]=n;}assert.throws(()=>core.mergeNotes([],randomUUID(),pending));
});

test('seven-day cleanup removes posted notes in every account while preserving drafts and layout',()=>{
  const now=2000000, old={...note('Old'),created:now-core.NOTE_RETENTION_SECONDS}, fresh={...note('Fresh'),created:now-core.NOTE_RETENTION_SECONDS+1};
  const draft={text:'Keep me'},store={apps:[{id:'game'}],accounts:{offline:{privateNotes:[old,fresh],draft,pending:{}},other:{remoteNotes:[old,fresh],pending:{[old.id]:old,[fresh.id]:fresh,deleted:null}}}};
  assert.equal(core.pruneNotes(store,now),3);assert.deepEqual(store.accounts.offline.privateNotes,[fresh]);assert.deepEqual(store.accounts.other.remoteNotes,[fresh]);assert.equal(store.accounts.offline.draft,draft);assert.deepEqual(store.apps,[{id:'game'}]);assert.equal(store.accounts.other.pending.deleted,null);
  assert.deepEqual(core.mergeNotes([],randomUUID(),{[old.id]:old},now),[]);
});
test('Mac uppercase UUIDs update and retract the same Windows/server source ID without duplicates',()=>{const owner=randomUUID(),n=note('Shared'),remote=[{...n,id:randomUUID(),sourceID:n.id,ownerID:owner}],upper=n.id.toUpperCase();assert.equal(core.mergeNotes(remote,owner,{[upper]:{...n,id:upper,text:'Edited'}}).length,1);assert.equal(core.mergeNotes(remote,owner,{[upper]:{...n,id:upper,text:'Edited'}})[0].text,'Edited');assert.deepEqual(core.mergeNotes(remote,owner,{[upper]:null}),[]);});
test('combined own private/shared journal bounds match Mac, account-isolated and deletion-aware',()=>{const account=randomUUID(),privateNotes=Array.from({length:200},()=>note('Private')),doc={privateNotes,pending:{},remoteNotes:[],draft:{drawing:[]}};core.validateJournalChange(doc,account,{...privateNotes[0],text:'Edit'});assert.throws(()=>core.validateJournalChange(doc,account,note('New')));const points=Array(20000).fill({x:.5,y:.5}),drawn=Array.from({length:3},()=>({...note('Drawing'),drawing:[{eraser:false,points}],drawingDescription:'Dots'}));core.validateJournalChange({privateNotes:drawn,pending:{}},account,drawn[0]);assert.throws(()=>core.validateJournalChange({privateNotes:drawn,pending:{}},account,{...note('Extra'),drawing:[{eraser:false,points:[{x:0,y:0}]}]}));});

test('legacy Mac-imported note keys normalize once without changing Mii identities or discussion',()=>{const n=note('Mac import'),id=n.id.toUpperCase(),r={id:randomUUID().toUpperCase(),text:'Local'};n.id=id;n.author.id=n.author.id.toUpperCase();n.replies=[r];const avatarID=n.author.id,doc={privateNotes:[n],pending:{[id]:null},ownedMeta:{[id]:{replies:[r]}},readNotes:[id]},store={accounts:{offline:doc}};assert.equal(core.normalizeNoteIDs(store),true);assert.equal(doc.privateNotes[0].id,id.toLowerCase());assert.equal(doc.privateNotes[0].author.id,avatarID);assert.equal(doc.pending[id.toLowerCase()],null);assert.equal(doc.ownedMeta[id.toLowerCase()].replies[0].text,'Local');assert.equal(doc.readNotes[0],id.toLowerCase());assert.equal(core.normalizeNoteIDs(store),false);});
