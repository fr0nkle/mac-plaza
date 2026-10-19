'use strict';
const name = note => note.displayName || note.author?.name || 'A friend';
const topicID = topic => topic?.steamAppID ? 'steam:'+topic.steamAppID : topic?.bundleID ? 'bundle:'+topic.bundleID : 'plaza';
const identity=value=>String(value||'').toLowerCase();
const recent=(a,now=Date.now()/1000)=>Number.isFinite(a.observedAt)&&now-a.observedAt>=-60&&now-a.observedAt<(a.source==='discord'&&a.active===false?7200:1800);
const fold=s=>String(s||'').normalize('NFD').replace(/\p{Diacritic}/gu,'').replace(/[^\p{L}\p{N}]/gu,'').toLocaleLowerCase('en-US');
function matchActivity(activities,apps,now=Date.now()/1000){
 for(const a of [...(activities||[])].filter(a=>recent(a,now)).sort((a,b)=>Number(b.active!==false)-Number(a.active!==false)||b.observedAt-a.observedAt)){
  const bundle=a.bundleID?apps.findIndex(app=>app.bundleID===a.bundleID):-1;if(bundle>=0)return bundle;
  const matches=apps.map((app,i)=>fold(app.label)===fold(a.name)?i:-1).filter(i=>i>=0);if(matches.length===1)return matches[0];
 }return -1;
}

function friendGames(friends,apps,now=Date.now()/1000){const seen=new Set(),result=[];for(const friend of friends)for(const a of friend.activities||[]){if(a.source!=='discord'||!recent(a,now)||(a.active!==false&&['offline','unknown'].includes(friend.presence)))continue;const i=matchActivity([a],apps,now);if(i>=0){const key=topicID(apps[i]);if(!seen.has(key)){seen.add(key);result.push(apps[i]);}}}return result;}
function friendFor(note,friends){
  const owners=friends.filter(f=>note.ownerID&&identity(f.id)===identity(note.ownerID)),linked=friends.filter(f=>note.discordID&&f.discordID===note.discordID);
  if(owners.length>1||linked.length>1)return;
  if(owners[0]){if(note.discordID&&owners[0].discordID&&note.discordID!==owners[0].discordID)return;if(linked[0]&&identity(linked[0].id)!==identity(owners[0].id))return;return owners[0];}return linked[0];
}
function conflictingIdentity(note,friends){return !friendFor(note,friends)&&friends.some(f=>note.ownerID&&identity(f.id)===identity(note.ownerID)||note.discordID&&f.discordID===note.discordID);}
function catalog(notes,apps=[],accountID){
  const communities=new Map(apps.map(a=>[topicID(a),a.label])),seen=new Set(),entries=[];
  for(const note of notes){const own=note.private||note.pending||note.ownerID===accountID,key=(own?'own:':note.ownerID+':')+(note.sourceID||note.id);if(seen.has(key))continue;seen.add(key);const section=topicID(note.topic),label=communities.get(section)||note.topic?.label||'The Plaza';if(section!=='plaza')communities.set(section,label);entries.push({note,own,section,label});}
  const sections=[['all','All Notes'],['mine','My Notes'],['friends','Friends’ Notes'],['public','Public Posts'],['plaza','The Plaza'],...[...communities].filter(([id])=>id!=='plaza').sort((a,b)=>a[1].localeCompare(b[1]))].map(([id,label])=>({id,label,count:entries.filter(e=>matches(e,id)).length,app:apps.find(a=>topicID(a)===id)}));
  return{entries,sections};
}
function matches(entry,section){return section==='all'||(section==='mine'&&entry.own)||(section==='friends'&&!entry.own&&entry.note.isFriend!==false)||(section==='public'&&!entry.note.private&&entry.note.audience==='public')||entry.section===section;}
function filtered(index,section='all',query='',sort='newest'){
  const fold=s=>String(s||'').normalize('NFD').replace(/\p{Diacritic}/gu,'').toLocaleLowerCase(),q=fold(query.trim());
  return index.entries.filter(e=>matches(e,section)&&(!q||[e.note.text,name(e.note),e.note.drawingDescription,e.label].some(s=>fold(s).includes(q)))).sort((a,b)=>(sort==='liked'?(b.note.likeCount||0)-(a.note.likeCount||0):0)||(sort==='oldest'?a.note.created-b.note.created:b.note.created-a.note.created)||a.note.id.localeCompare(b.note.id)).map(e=>e.note);
}
// Initial history is quiet; the account-scoped monotonic cursor survives restarts.
function activityCursor(previous,activities){const maximum=Math.max(previous||0,...activities.map(a=>a.id),0);return{cursor:maximum,fresh:previous==null?[]:activities.filter(a=>!a.read&&a.id>previous)};}
function orderedCommunities(index,{history=[],apps=[],friends=[],alphabetic=false,random=Math.random,now=Date.now()}={}){
  const communities=index.sections.filter(s=>!['all','mine','friends','public'].includes(s.id)),scores=new Map();
  for(const e of index.entries)if(e.section!=='plaza')scores.set(e.section,(scores.get(e.section)||0)+1+Math.max(0,e.note.likeCount||0)+(e.note.replies?.length||0));
  for(const entry of history)if(now-entry.at<90*86400000){const app=apps.find(a=>a.id===entry.id);if(app){const id=topicID(app);scores.set(id,(scores.get(id)||0)+1);}}
  for(const friend of friends)for(const app of friendGames([friend],apps,now/1000)){const id=topicID(app);scores.set(id,(scores.get(id)||0)+4);}
  const rest=communities.filter(s=>s.id!=='plaza');for(let i=rest.length-1;i>0;i--){const j=Math.floor(random()*(i+1));[rest[i],rest[j]]=[rest[j],rest[i]];}
  const ranks=new Map(rest.map((s,i)=>[s.id,i]));rest.sort((a,b)=>alphabetic?a.label.localeCompare(b.label,undefined,{numeric:true,sensitivity:'base'}):(scores.get(b.id)||0)-(scores.get(a.id)||0)||ranks.get(a.id)-ranks.get(b.id));
  return [...communities.filter(s=>s.id==='plaza'),...rest];
}
const api={friendGames,recent,matchActivity,name,topicID,catalog,filtered,activityCursor,orderedCommunities,friendFor,conflictingIdentity};
if(typeof module!=='undefined')module.exports=api;else window.PlazaCatalog=api;
