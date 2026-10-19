'use strict';
// Mac Plaza v2 uses Foundation's 2001 epoch. Only this account's authored content
// enters an export; received posts and their service-owned discussions do not.
const core=require('./core.cjs'),epoch=978307200;
const appFor=(topic,apps)=>topic?apps.find(a=>topic.steamAppID?a.steamAppID===topic.steamAppID:!a.steamAppID&&a.bundleID===topic.bundleID):null;
function exportDocument(document,apps,accountID){
 const preferences={...document.settings,rotatingHomeScreen:document.settings?.rotateHome,population:document.settings?.population||160,pauseMotion:!!document.settings?.pauseMotion,pausePosts:!!document.settings?.pausePosts,privatePresentation:!!document.settings?.privatePresentation,safeMode:!!document.settings?.safeMode};delete preferences.rotateHome;
 const own=new Map();
 if(accountID)for(const n of document.remoteNotes||[])if(n.ownerID===accountID)own.set(n.sourceID||n.id,{...n,id:n.sourceID||n.id,author:document.avatar,private:false});
 for(const [id,n]of Object.entries(document.pending||{}))if(n)own.set(id,{...n,id,author:document.avatar,private:false});else own.delete(id);
 for(const [id,meta]of Object.entries(document.ownedMeta||{}))if(own.has(id))own.set(id,{...own.get(id),replies:[...(own.get(id).replies||[]).filter(r=>r.ownerID),...(meta.replies||[])]});
 for(const n of document.privateNotes||[])own.set(n.id,{...n,private:true});
 const notes=[...own.values()].map(n=>({id:n.id,authorID:n.author.id,author:n.author.name,text:n.text,drawing:n.drawing,drawingDescription:n.drawingDescription,created:n.created-epoch,acknowledged:!!(n.private?n.liked:document.ownedMeta?.[n.id]?.liked),read:!!n.read||(document.readNotes||[]).includes(n.id),shared:!n.private,audience:n.private?'private':n.audience||'friends',
   replies:(n.replies||[]).filter(r=>n.private||!r.ownerID).map(r=>({id:r.id,authorID:r.author.id,author:r.author.name,text:r.text,created:(r.created||n.created)-epoch})),appID:appFor(n.topic,apps)?.id}));
 const draft=document.draft||{};
 return{version:2,avatars:document.avatars,primaryAvatarID:document.avatar.id,apps:apps.map(a=>({id:a.id,label:a.label,bundleID:a.bundleID,...(a.steamAppID?{steamAppID:a.steamAppID}:{}),...(a.customIcon||/^data:image\/(?:png|jpeg|webp|gif);base64,/.test(a.icon||'')?{customIcon:a.customIcon||a.icon.split(',')[1]}:{})})),preferences,notes,
   draft:{text:draft.text||'',drawing:draft.drawing||[],description:draft.drawingDescription||'',authorID:draft.authorID||document.avatar.id,appID:appFor(draft.topic,apps)?.id,shared:core.draftVisibility(draft)!=='private',audience:core.draftVisibility(draft)}};
}
function importDocument(portable,current,accountID){
 const next=structuredClone(current);next.avatars=portable.avatars;next.avatar=next.avatars.find(a=>a.id===portable.primaryAvatarID)||next.avatars[0];next.settings={...portable.preferences,rotateHome:portable.preferences.rotatingHomeScreen!==false};delete next.settings.rotatingHomeScreen;
 const author=(id,name)=>next.avatars.find(a=>a.id===id)||{...next.avatar,id,name};
 const topic=id=>{const a=portable.apps.find(a=>a.id===id);return a?{label:a.label,bundleID:a.bundleID,steamAppID:a.steamAppID||null}:null;};
 const notes=portable.notes.map(n=>({id:core.uuidKey(n.id),author:author(n.authorID,n.author),text:n.text,drawing:n.drawing,drawingDescription:n.drawingDescription,created:n.created+epoch,liked:!!n.acknowledged,audience:n.shared===true?n.audience||'friends':'private',
   replies:(n.replies||[]).map(r=>({id:r.id,author:author(r.authorID,r.author),text:r.text,created:r.created+epoch})),topic:topic(n.appID)}));
 next.privateNotes=[];next.pending||={};next.ownedMeta||={};next.readNotes=portable.notes.filter(n=>n.read).map(n=>core.uuidKey(n.id));for(const n of notes){core.validateNote(n);if(core.expired(n))continue;if(n.audience==='private'){delete next.ownedMeta[n.id];next.privateNotes.push(n);if(accountID)next.pending[n.id]=null;else delete next.pending[n.id];}else{next.pending[n.id]=n;next.ownedMeta[n.id]={replies:n.replies,liked:n.liked,created:n.created};}}
 next.draft={text:portable.draft?.text||'',drawing:portable.draft?.drawing||[],drawingDescription:portable.draft?.description||'',visibility:portable.draft?core.draftVisibility(portable.draft):'public',authorID:portable.draft?.authorID||next.avatar.id,topic:topic(portable.draft?.appID)};return next;
}
module.exports={exportDocument,importDocument};
