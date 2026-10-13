'use strict';
// Mac Plaza's portable document format uses Foundation's 2001 date epoch.
const core=require('./core.cjs');
const epoch=978307200;
function exportDocument(document,apps){
  const preferences={...document.settings,rotatingHomeScreen:document.settings?.rotateHome,population:document.settings?.population||160,pauseMotion:!!document.settings?.pauseMotion,pausePosts:!!document.settings?.pausePosts,privatePresentation:!!document.settings?.privatePresentation,safeMode:!!document.settings?.safeMode};delete preferences.rotateHome;
  return{version:2,avatars:document.avatars,primaryAvatarID:document.avatar.id,apps:apps.map(a=>({id:a.id,label:a.label,bundleID:a.bundleID,...(a.steamAppID?{steamAppID:a.steamAppID}:{})})),preferences,
    notes:document.privateNotes.map(n=>({id:n.id,authorID:n.author.id,author:n.author.name,text:n.text,drawing:n.drawing,drawingDescription:n.drawingDescription,created:n.created-epoch,acknowledged:!!n.liked,shared:false})),
    draft:{text:document.draft.text||'',drawing:document.draft.drawing||[],description:document.draft.drawingDescription||'',authorID:document.avatar.id}};
}
function importDocument(portable,current){
  const next=structuredClone(current);next.avatars=portable.avatars;next.avatar=next.avatars.find(a=>a.id===portable.primaryAvatarID)||next.avatars[0];next.settings={...portable.preferences,rotateHome:portable.preferences.rotatingHomeScreen!==false};delete next.settings.rotatingHomeScreen;
  next.privateNotes=portable.notes.map(n=>({id:n.id,author:next.avatars.find(a=>a.id===n.authorID)||{...next.avatar,id:n.authorID,name:n.author},text:n.text,drawing:n.drawing,drawingDescription:n.drawingDescription,created:n.created+epoch}));
  for(const n of next.privateNotes)core.validateNote(n);
  next.draft={text:portable.draft?.text||'',drawing:portable.draft?.drawing||[],drawingDescription:portable.draft?.description||''};return next;
}
module.exports={exportDocument,importDocument};
