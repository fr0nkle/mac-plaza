'use strict';
// Real Mac Swift models + Windows publisher/transport + in-memory existing
// backend. No external requests, personal credentials, or production writes.
const assert=require('node:assert/strict'),path=require('node:path'),{spawn}=require('node:child_process'),{randomUUID}=require('node:crypto');
const {Engine}=require('../src/engine.cjs'),{ServiceClient}=require('../src/service-client.cjs'),core=require('../src/core.cjs'),portable=require('../src/portable.cjs');
async function main(){
  const fixture=spawn(process.env.PYTHON||'python3',[path.join(__dirname,'service_fixture.py')],{stdio:['ignore','pipe','pipe']});
  let engine;const timeout=setTimeout(()=>{fixture.kill();process.exitCode=1;},60000);
  try{
    const auth=await new Promise((resolve,reject)=>{let text='';fixture.stdout.on('data',chunk=>{text+=chunk;if(text.includes('\n'))resolve(JSON.parse(text.split('\n')[0]));});fixture.on('error',reject);fixture.on('exit',code=>reject(Error('Fixture exited '+code)));fixture.stderr.on('data',chunk=>process.stderr.write(chunk));});
    assert.equal(new URL(auth.origin).hostname,'127.0.0.1');
    const client=new ServiceClient(),call=(token,method,route,body)=>client.request(method,'/v1/'+route,body,{origin:auth.origin,token});
    engine=new Engine(false);
    const windows=core.avatar('Windows Mii');windows.features.birthMonth=10;windows.features.birthDay=15;windows.features.creator='Private creator';
    const now=Date.now()/1000,note=(text,audience)=>({id:randomUUID(),author:windows,text,drawing:[{eraser:false,points:[{x:.25,y:.3},{x:.7,y:.6}]}],drawingDescription:'A wave 👋',created:now,topic:{label:'Portal 2',bundleID:'steam.app.620',steamAppID:620},...(audience?{audience}:{})});
    const publicNote=note('Hello Mac, from Windows!','public'),friendsNote=note('Friends Only from Windows','friends'),legacyNote=note('Legacy Friends Only');
    await call(auth.windows,'PUT','notes',{notes:[publicNote,friendsNote,legacyNote].map(core.wireNote),primaryAvatar:core.publicAvatar(windows)});
    const macFeed=(await call(auth.mac,'GET','notes/threads')).notes;
    for(const note of macFeed)assert.equal(note.author.features.birthDay,0);
    const decoded=await engine.call('sharedNotes',{notes:macFeed});assert.equal(decoded.notes.filter(n=>n.ownerID===auth.accountID).length,3);
    const strangerFeed=(await call(auth.stranger,'GET','notes/threads')).notes;
    assert.deepEqual(strangerFeed.map(n=>n.text),[publicNote.text]);assert.equal(strangerFeed[0].isFriend,false);
    await assert.rejects(call('invalid-session','GET','notes/threads'),e=>e.status===401);
    // Generate the Mac payload with shipping PlazaCore, rather than a second JS model.
    const doc=core.document();doc.avatar=core.avatar('Mac Primary');doc.avatar.hair=93;doc.avatar.features.birthMonth=2;doc.avatar.features.birthDay=29;doc.avatars=[doc.avatar];doc.privateNotes=[{...note('Hello Windows, from Mac!','public'),author:doc.avatar}];
    const exchange=portable.exportDocument(doc,[]);exchange.notes[0].shared=true;exchange.notes[0].audience='public';
    const published=await engine.call('publishNotes',{document:exchange});assert.equal(published.length,1);assert.equal(published[0].audience,'public');assert.equal(published[0].author.features.birthMonth,0);
    const game=published[0];game.topic={label:'Portal 2 on Mac',bundleID:'com.valvesoftware.portal2',steamAppID:620};
    await call(auth.mac,'PUT','notes',{notes:published,primaryAvatar:core.publicAvatar(doc.avatar)});
    const received=(await call(auth.windows,'GET','notes/threads')).notes.find(n=>n.text===game.text);core.validateNote(received);assert.equal(received.topic.steamAppID,620);assert.equal(received.author.name,'Mac Friend');assert.equal(received.author.hair,doc.avatar.hair);assert.equal(received.author.id,(await call(auth.windows,'GET','snapshot')).friends.find(f=>f.id===received.ownerID).avatar.id);assert.equal(received.displayName,'Mac Friend');
    const shared=(await call(auth.mac,'GET','notes/threads')).notes.find(n=>n.sourceID===publicNote.id);
    await call(auth.stranger,'PUT','notes/'+shared.id+'/like',{liked:true});
    const replyID=randomUUID();await call(auth.mac,'PUT','notes/'+shared.id+'/replies/'+replyID,{author:core.publicAvatar(doc.avatar),text:'Reply from Mac',displayName:'Forged name'});
    const thread=(await call(auth.windows,'GET','notes/threads')).notes.find(n=>n.id===shared.id);assert.equal(thread.likeCount,1);assert.equal(thread.replies[0].displayName,'Mac Friend');
    await engine.call('sharedNotes',{notes:[thread]});
    await assert.rejects(call(auth.stranger,'DELETE','notes/'+shared.id+'/replies/'+replyID),e=>e.status===403);
    const owned=(await call(auth.windows,'GET','notes/owned')).notes;
    const merged=core.mergeNotes(owned,auth.accountID,{[publicNote.id]:{...publicNote,audience:'friends'}});
    await call(auth.windows,'PUT','notes',{notes:merged,primaryAvatar:core.publicAvatar(windows)});
    assert(!(await call(auth.stranger,'GET','notes/threads')).notes.some(n=>n.id===shared.id));
    await assert.rejects(call(auth.stranger,'PUT','notes/'+shared.id+'/like',{liked:true}),e=>[403,404].includes(e.status));
    assert.equal((await call(auth.mac,'GET','notes/threads')).notes.find(n=>n.id===shared.id).audience,'friends');
    await call(auth.windows,'PUT','notes',{notes:core.mergeNotes((await call(auth.windows,'GET','notes/owned')).notes,auth.accountID,{[publicNote.id]:null})});
    assert(!(await call(auth.mac,'GET','notes/threads')).notes.some(n=>n.id===shared.id));
    const macOwner=received.ownerID;await call(auth.stranger,'POST','friends/block',{id:macOwner});assert(!(await call(auth.stranger,'GET','notes/threads')).notes.some(n=>n.ownerID===macOwner));
    const library=core.document(),secondary=core.avatar('Secondary');library.avatar=windows;library.avatars=[windows,secondary];library.remoteNotes=(await call(auth.windows,'GET','notes/owned')).notes;
    library.privateNotes=[{...note('Portable private','private'),author:secondary,replies:[{id:randomUUID(),author:secondary,text:'Local discussion',created:now}]}];library.draft={text:'Portable draft',visibility:'friends',drawing:[],drawingDescription:'',authorID:secondary.id,topic:publicNote.topic};
    const appID=randomUUID(),portableMac=await engine.call('portable',{document:portable.exportDocument(library,[{id:appID,label:'Portal 2',bundleID:'steam.app.620',steamAppID:620,path:'C:/local-only'}],auth.accountID)}),roundtrip=portable.importDocument(portableMac,core.document(),auth.accountID);
    assert.equal(roundtrip.privateNotes[0].author.name,'Secondary');assert.equal(roundtrip.privateNotes[0].replies[0].text,'Local discussion');assert.equal(roundtrip.privateNotes[0].created,now);assert.equal(Object.values(roundtrip.pending).filter(Boolean).length,2);assert(Object.values(roundtrip.pending).filter(Boolean).every(n=>n.audience==='friends'));assert.equal(roundtrip.draft.visibility,'friends');assert.equal(roundtrip.draft.topic.steamAppID,620);assert.equal(portableMac.apps[0].path,undefined);
    console.log('PASS: Mac Swift ↔ Windows wire and portable contracts, real local HTTP transport, shared primary Miis, Steam topics, drawings, three audiences/legacy privacy, verified Discord names, likes/replies, owner permissions, retraction, block precedence, unauthenticated rejection and Foundation-date/local-discussion/draft round trips.');
  }finally{clearTimeout(timeout);engine?.close();fixture.kill();}
}
main().catch(error=>{console.error(error);process.exitCode=1;});
