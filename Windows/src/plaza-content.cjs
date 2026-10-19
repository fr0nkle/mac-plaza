'use strict';
(()=>{
const catalog=typeof module!=='undefined'?require('./catalog.cjs'):window.PlazaCatalog,identity=id=>String(id||'').toLowerCase();
const {recent,matchActivity}=catalog;
function matchTopic(topic,apps){return topic?apps.findIndex(a=>topic.steamAppID?a.steamAppID===topic.steamAppID:!a.steamAppID&&a.bundleID===topic.bundleID):-1;}
function noteSpeech(note,{friends=[],avatars=[],primary,accountID}){
 const own=note.private||note.pending||accountID&&note.ownerID===accountID;
 if(own){const author=note.private?avatars.find(a=>identity(a.id)===identity(note.author.id)):primary;if(!author)return;return{...note,author,displayName:note.private?author.name:catalog.name(note)};}
 if(catalog.conflictingIdentity(note,friends))return;const friend=catalog.friendFor(note,friends);
 if(!friend&&(friends.some(f=>identity(f.avatar.id)===identity(note.author.id))||avatars.some(a=>identity(a.id)===identity(note.author.id))))return;
 return{...note,author:friend?.avatar||note.author,displayName:catalog.name(note)};
}
function roster({avatars,primary,friends=[],notes=[],apps=[],population=160,accountID}){
 const context={avatars,primary,friends,accountID},home=notes.filter(n=>!n.private&&!n.pending&&n.ownerID!==accountID&&(!n.topic||matchTopic(n.topic,apps)>=0)),authors=home.map(n=>noteSpeech(n,context)?.author).filter(Boolean),seen=new Set(avatars.map(a=>identity(a.id))),visitors=[];
 for(const a of [...authors,...friends.map(f=>f.avatar)])if(!seen.has(identity(a.id))){seen.add(identity(a.id));visitors.push(a);}
 const chosen=avatars.concat(visitors.slice(0,Math.max(0,population-avatars.length))).slice(0,population),gathering={};
 for(const f of friends){const i=matchActivity(f.activities,apps);if(i>=0)gathering[identity(f.avatar.id)]=i;}
 for(const n of [...home].reverse()){const speaker=noteSpeech(n,context)?.author,i=matchTopic(n.topic,apps);if(speaker&&i>=0)gathering[identity(speaker.id)]=i;}
 return{avatars:chosen,gathering};
}
function friendSpeech(friend,variation=0,now=Date.now()/1000){
 if(!/^\d{1,20}$/.test(friend.discordID||'')||(BigInt(friend.discordID)===0n||BigInt(friend.discordID)>=2n**64n))return;
 const texts=[],status=friend.customStatus;if(status?.discordID===friend.discordID&&now-status.observedAt>=-60&&now-status.observedAt<90&&!['offline','unknown'].includes(friend.presence)&&status.text?.trim())texts.push(status.text);
 for(const a of [...(friend.activities||[])].filter(a=>a.source==='discord'&&recent(a,now)).sort((a,b)=>Number(b.active!==false)-Number(a.active!==false)||b.observedAt-a.observedAt)){const text=a.active===false?friend.displayName+' was recently playing '+a.name:'Playing '+a.name;if(!texts.includes(text))texts.push(text);}
 if(!texts.length)return;return{id:'discord-'+friend.id+'-'+variation%texts.length,author:friend.avatar,displayName:friend.displayName,text:texts[Math.max(0,variation)%texts.length],drawing:[],drawingDescription:'',friendID:friend.id};
}
function speech({notes,friends=[],avatars,primary,accountID,apps,rendered,presentation,variation=0,cursor=0}){
 const context={friends,avatars,primary,accountID},journal=notes.filter(n=>!n.topic||n.private||n.pending||n.ownerID===accountID||matchTopic(n.topic,apps)>=0).sort((a,b)=>Number(!!a.read)-Number(!!b.read)||b.created-a.created),rotated=journal.slice(cursor%Math.max(1,journal.length)).concat(journal.slice(0,cursor%Math.max(1,journal.length))),candidates=[];
 if(presentation==='friends')candidates.push(...friends.map(f=>friendSpeech(f,variation)).filter(Boolean));
 candidates.push(...rotated.map(n=>noteSpeech(n,context)).filter(Boolean).slice(0,6));const seen=new Set(),ids=new Set(rendered.map(identity));
 return candidates.filter(n=>ids.has(identity(n.author.id))&&!seen.has(identity(n.author.id))&&seen.add(identity(n.author.id)));
}
function placements(anchors,size,card,obstacles=[],limit=3){
 const result=[],reserved=[...obstacles];if(limit<=0||size.width<=card.width+24||size.height<=card.height+24)return result;
 const intersects=(a,b)=>a.x<b.x+b.width&&a.x+a.width>b.x&&a.y<b.y+b.height&&a.y+a.height>b.y;
 for(let i=0;i<anchors.length;i++){const p=anchors[i];if(!Number.isFinite(p.x)||!Number.isFinite(p.y)||p.x<12||p.x>size.width-12||p.y<12||p.y>size.height-12)continue;let chosen;
  for(const rise of [8,24,40]){for(const shift of [0,-.2,.2,-.4,.4]){const r={x:Math.min(size.width-card.width-12,Math.max(12,p.x-card.width/2+shift*card.width)),y:p.y-card.height-rise,...card};if(r.y>=12&&r.y+r.height<p.y&&r.y+r.height<size.height-30&&p.x>=r.x+27&&p.x<=r.x+r.width-27&&!reserved.some(o=>intersects(o,{x:r.x-6,y:r.y-6,width:r.width+12,height:r.height+12}))){chosen=r;break;}}if(chosen)break;}
  if(chosen){result.push({index:i,...chosen});reserved.push(chosen);if(result.length===limit)break;}
 }return result;
}
const api={recent,matchTopic,matchActivity,noteSpeech,roster,friendSpeech,speech,placements};if(typeof module!=='undefined')module.exports=api;else window.PlazaContent=api;
})();
