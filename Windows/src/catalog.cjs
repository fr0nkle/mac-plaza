'use strict';
const name = note => note.displayName || note.author?.name || 'A friend';
const topicID = topic => topic?.steamAppID ? 'steam:'+topic.steamAppID : topic?.bundleID ? 'bundle:'+topic.bundleID : 'plaza';
function catalog(notes,apps=[],accountID){
  const communities=new Map(apps.map(a=>[topicID(a),a.label])),seen=new Set(),entries=[];
  for(const note of notes){const own=note.private||note.pending||note.ownerID===accountID,key=(own?'own:':note.ownerID+':')+(note.sourceID||note.id);if(seen.has(key))continue;seen.add(key);const section=topicID(note.topic),label=communities.get(section)||note.topic?.label||'The Plaza';if(section!=='plaza')communities.set(section,label);entries.push({note,own,section,label});}
  const sections=[['all','All Notes'],['mine','My Notes'],['friends','Friends’ Notes'],['plaza','The Plaza'],...[...communities].filter(([id])=>id!=='plaza').sort((a,b)=>a[1].localeCompare(b[1]))].map(([id,label])=>({id,label,count:entries.filter(e=>matches(e,id)).length,app:apps.find(a=>topicID(a)===id)}));
  return{entries,sections};
}
function matches(entry,section){return section==='all'||(section==='mine'&&entry.own)||(section==='friends'&&!entry.own)||entry.section===section;}
function filtered(index,section='all',query='',sort='newest'){
  const fold=s=>String(s||'').normalize('NFD').replace(/\p{Diacritic}/gu,'').toLocaleLowerCase(),q=fold(query.trim());
  return index.entries.filter(e=>matches(e,section)&&(!q||[e.note.text,name(e.note),e.note.drawingDescription,e.label].some(s=>fold(s).includes(q)))).sort((a,b)=>(sort==='liked'?(b.note.likeCount||0)-(a.note.likeCount||0):0)||(sort==='oldest'?a.note.created-b.note.created:b.note.created-a.note.created)||a.note.id.localeCompare(b.note.id)).map(e=>e.note);
}
// Initial history is quiet; the account-scoped monotonic cursor survives restarts.
function activityCursor(previous,activities){const maximum=Math.max(previous||0,...activities.map(a=>a.id),0);return{cursor:maximum,fresh:previous==null?[]:activities.filter(a=>!a.read&&a.id>previous)};}
const api={name,topicID,catalog,filtered,activityCursor};
if(typeof module!=='undefined')module.exports=api;else window.PlazaCatalog=api;
