const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const core=require('../src/core.cjs'),{catalog,filtered}=require('../src/catalog.cjs'),portable=require('../src/portable.cjs');
const note=(audience)=>({id:randomUUID(),author:core.avatar(),text:'Hello Mac 👋',drawing:[],drawingDescription:'',created:Date.now()/1000,...(audience?{audience}:{})});
test('three audiences match Mac; missing wire audiences retain friends-only privacy',()=>{
  assert.equal(core.wireNote(note()).audience,'friends');
  for(const audience of ['public','friends'])assert.equal(core.wireNote(note(audience)).audience,audience);
  for(const audience of ['private','everyone','',false,[]])assert.throws(()=>core.wireNote({...note(),audience}));
  const doc=core.document();assert.equal(doc.draft.visibility,'public');
});
test('upgrade keeps old pending posts and resumed public-labelled drafts friends-only exactly once',()=>{
  const pending=note(),store={accounts:{offline:{draft:{text:'Saved draft',visibility:'public'},pending:{[pending.id]:pending}},other:{draft:{visibility:'private'}}}};
  assert.equal(core.migrateAudiences(store),true);assert.equal(store.accounts.offline.draft.visibility,'friends');assert.equal(pending.audience,'friends');assert.equal(store.accounts.other.draft.visibility,'private');
  store.accounts.offline.draft.visibility='public';assert.equal(core.migrateAudiences(store),false);assert.equal(store.accounts.offline.draft.visibility,'public');
});
test('republishing a primary Mii never broadens Mac posts or publishes birthday/creator data',()=>{
  const ownerID=randomUUID(),publicNote=note('public'),friendsNote=note('friends'),old=note();
  const remote=[publicNote,friendsNote,old].map(n=>({...n,sourceID:n.id,id:randomUUID(),ownerID}));
  remote[0].author.features.birthDay=15;remote[0].author.features.birthMonth=10;remote[0].author.features.creator='Private';
  const merged=core.mergeNotes(remote,ownerID,{});assert.deepEqual(merged.map(n=>n.audience),['public','friends','friends']);assert.equal(merged[0].author.features.birthDay,0);assert.equal(remote[0].author.features.birthDay,15);
});
test('public strangers do not appear in Friends Notes or create friendships',()=>{
  const notes=[{...note('public'),isFriend:false,ownerID:'stranger'},{...note('friends'),isFriend:true,ownerID:'friend'},{...note('public'),ownerID:'me'},{...note(),private:true}];
  const index=catalog(notes,[],'me');assert.equal(filtered(index,'friends').length,1);assert.equal(filtered(index,'public').length,2);assert.equal(filtered(index,'all').length,4);
});
test('Mac portable drafts round trip each audience; absent legacy audience stays friends-only',()=>{
  const doc=core.document();doc.avatars=[doc.avatar];
  for(const visibility of ['private','friends','public']){doc.draft.visibility=visibility;const value=portable.exportDocument(doc,[]);assert.equal(value.draft.audience,visibility);assert.equal(portable.importDocument(value,doc).draft.visibility,visibility);}
  const legacy={...portable.exportDocument(doc,[]),draft:{text:'Saved old Mac draft',drawing:[],description:''}};
  assert.equal(portable.importDocument(legacy,doc).draft.visibility,'friends');
});
