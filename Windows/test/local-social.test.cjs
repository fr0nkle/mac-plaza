const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const local=require('../src/local-social.cjs'),core=require('../src/core.cjs');
const now=1800000000;
function fixture(){const account=randomUUID(),author=core.avatar('Me'),note={id:randomUUID(),ownerID:randomUUID(),author,text:'Hello',created:now-60,drawing:[],drawingDescription:'',likeCount:2,liked:false,replies:[]};return{account,author,note,document:{remoteNotes:[note]}};}
test('offline like intentions coalesce and survive restart',()=>{
  const {account,note,document}=fixture();local.enqueue(document,{noteID:note.id,liked:true},account,now);local.enqueue(document,{noteID:note.id,liked:true},account,now);
  assert.equal(document.outbox.length,1);assert.equal(local.displayNotes(JSON.parse(JSON.stringify(document)),account,now)[0].likeCount,3);
  local.enqueue(document,{noteID:note.id,liked:false},account,now);assert.equal(document.outbox.length,1);assert.equal(local.displayNotes(document,account,now)[0].likeCount,2);
});
test('late acknowledgements preserve newer reply edits and reply IDs',()=>{
  const {account,note,document,author}=fixture(),replyID=randomUUID();
  const old=local.enqueue(document,{noteID:note.id,replyID,author,text:'First'},account,now);
  const next=local.enqueue(document,{noteID:note.id,replyID,author,text:'Edited'},account,now);
  local.acknowledge(document,old,account,true);
  assert.equal(document.outbox[0].queueID,next.queueID);const replies=local.displayNotes(document,account,now)[0].replies;
  assert.equal(replies.length,1);assert.equal(replies[0].id,replyID);assert.equal(replies[0].text,'Edited');
});
test('revoked and expired notes discard queued delivery',()=>{
  const {account,note,document}=fixture();local.enqueue(document,{noteID:note.id,liked:true},account,now);
  document.remoteNotes=[];local.prune(document,now);assert.equal(document.outbox.length,0);
  document.remoteNotes=[note];local.enqueue(document,{noteID:note.id,liked:true},account,now);local.prune(document,now+core.NOTE_RETENTION_SECONDS);assert.equal(document.outbox.length,0);
});
test('queue enforces reply ownership, limits and public appearance stripping',()=>{
  const {account,note,document,author}=fixture(),replyID=randomUUID();author.features.creator='private';author.features.birthDay=12;
  local.enqueue(document,{noteID:note.id,replyID,author,text:'Reply'},account,now);assert.equal(document.outbox[0].author.features.creator,'');assert.equal(document.outbox[0].author.features.birthDay,0);
  note.replies=[{id:replyID,ownerID:randomUUID(),text:'Other'}];document.outbox=[];
  assert.throws(()=>local.enqueue(document,{noteID:note.id,replyID,author,text:'Spoofed'},account,now));
  assert.throws(()=>local.enqueue(document,{noteID:note.id,replyID,remove:true},account,now));
  assert.throws(()=>local.enqueue(document,{noteID:note.id,replyID:randomUUID(),author,text:' '},account,now));
});
