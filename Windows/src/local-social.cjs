'use strict';
const {randomUUID}=require('node:crypto');
const core=require('./core.cjs');
const uuid=value=>typeof value==='string'&&/^[\da-f]{8}-(?:[\da-f]{4}-){3}[\da-f]{12}$/i.test(value);
function enqueue(document,change,accountID,now=Date.now()/1000){
  if(!uuid(accountID)||!uuid(change.noteID))throw Error('Connect to the sharing service once before interacting.');
  const note=(document.remoteNotes||[]).find(n=>n.id===change.noteID&&!core.expired(n,now));
  if(!note)throw Error('This public note is no longer available.');
  const item={queueID:randomUUID(),noteID:note.id,created:now,expiresAt:note.created+core.NOTE_RETENTION_SECONDS};
  if(Object.hasOwn(change,'liked')){if(typeof change.liked!=='boolean')throw Error('Invalid like.');item.liked=change.liked;}
  else{
    if(!uuid(change.replyID))throw Error('Invalid reply identity.');item.replyID=change.replyID;
    const replies=displayNotes(document,accountID,now).find(n=>n.id===note.id)?.replies||[],old=replies.find(r=>r.id===item.replyID);
    if(change.remove){if(!old||(old.ownerID!==accountID&&note.ownerID!==accountID))throw Error('You cannot remove this reply.');item.remove=true;}
    else{
      if(old&&old.ownerID!==accountID)throw Error('Only the reply author can edit it.');
      if(!old&&replies.length>=50)throw Error('This note has reached its reply limit.');
      if(typeof change.text!=='string'||![...change.text.trim()].length||[...change.text.trim()].length>280)throw Error('Write a reply up to 280 characters.');
      item.text=change.text.trim();item.author=core.publicAvatar(change.author);item.displayName=change.displayName;
    }
  }
  const queue=(document.outbox||[]).filter(i=>i.expiresAt>now&&(i.noteID!==item.noteID||i.replyID!==item.replyID));
  if(queue.length>=200)throw Error('The sharing queue is full. Connect to deliver pending changes.');
  document.outbox=[...queue,item];return item;
}
function displayNotes(document,accountID,now=Date.now()/1000){
  const notes=structuredClone((document.remoteNotes||[]).filter(n=>!core.expired(n,now)));
  for(const item of document.outbox||[]){
    if(item.expiresAt<=now)continue;const note=notes.find(n=>n.id===item.noteID);if(!note)continue;
    if(Object.hasOwn(item,'liked')){const old=!!note.liked;note.likeCount=Math.max(0,(note.likeCount||0)+(old===item.liked?0:item.liked?1:-1));note.liked=item.liked;}
    else{const old=note.replies?.find(r=>r.id===item.replyID);note.replies=(note.replies||[]).filter(r=>r.id!==item.replyID);if(!item.remove)note.replies.push({id:item.replyID,ownerID:accountID,author:item.author,text:item.text,displayName:item.displayName,created:old?.created||item.created});note.replies.sort((a,b)=>a.created-b.created);}
  }
  return notes;
}
function acknowledge(document,item,accountID,commit){
  if(commit)document.remoteNotes=displayNotes({...document,outbox:[item]},accountID);
  document.outbox=(document.outbox||[]).filter(i=>i.queueID!==item.queueID);
}
function prune(document,now=Date.now()/1000){
  const visible=new Set((document.remoteNotes||[]).filter(n=>!core.expired(n,now)).map(n=>n.id));
  document.outbox=(document.outbox||[]).filter(i=>i.expiresAt>now&&visible.has(i.noteID));
}
module.exports={enqueue,displayNotes,acknowledge,prune};
