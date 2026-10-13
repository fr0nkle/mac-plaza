'use strict';
const $ = selector => document.querySelector(selector);
let state, snapshot, notes = [], editing = null, drawing = [], erasing = false, stroke = null, loginTimer, refreshing = false;
const call = (action, value) => window.plaza.call(action, value);
function element(tag, text, className) { const node=document.createElement(tag);if(text!==undefined)node.textContent=text;if(className)node.className=className;return node; }
function button(text, action) {const node=element('button',text);node.type='button';node.addEventListener('click',()=>run(action));return node;}
function status(text) {$('#status').textContent=text;}
async function run(action) {try{return await action();}catch(error){status(error.message);return null;}}
function view(id) {for(const node of document.querySelectorAll('.view'))node.hidden=node.id!==id;for(const node of document.querySelectorAll('[data-view]'))node.classList.toggle('active',node.dataset.view===id);}
function apply(value) {
  state=value;snapshot=value.snapshot===undefined?snapshot:value.snapshot;
  notes=value.notes || value.document.remoteNotes || [];
  if(!state.connected){snapshot=null;notes=[];}
  $('#connection').textContent=state.connected?`Connected · ${snapshot?.account?.displayName || 'Discord'}`:'Local plaza · Offline notes';
  $('#service').value=state.origin;$('#service').disabled=state.connected;$('#connect').disabled=state.connected;$('#disconnect').disabled=!state.connected;
  $('#account-info').textContent=state.connected?`Signed in as ${snapshot?.account?.displayName || 'your Discord account'}. Your accepted friends can read public notes on Mac and Windows.`:'Connect Discord to share notes with Plaza friends. Private notes work offline.';
  $('#version').textContent=`Plaza for Windows ${state.version} · Windows 10 / 11, 64-bit`;
  $('#pending').textContent=Object.keys(state.document.pending).length?'You have saved changes waiting to sync. Keep Plaza open or choose Refresh to retry.':'';
  renderNotes();renderFriends();loadMaker();plazaScene.update(state.document.avatar,snapshot?.friends||[]);
}
function renderDrawing(canvas, strokes) {
  const c=canvas.getContext('2d');c.clearRect(0,0,canvas.width,canvas.height);c.lineCap='round';c.lineJoin='round';
  for(const s of strokes){c.globalCompositeOperation=s.eraser?'destination-out':'source-over';c.strokeStyle='#253d4c';c.lineWidth=(s.eraser?18:3)*canvas.width/600;c.beginPath();for(let i=0;i<s.points.length;i++){const p=s.points[i];if(i)c.lineTo(p.x*canvas.width,p.y*canvas.height);else c.moveTo(p.x*canvas.width,p.y*canvas.height);}if(s.points.length===1)c.lineTo(s.points[0].x*canvas.width+.1,s.points[0].y*canvas.height);c.stroke();}c.globalCompositeOperation='source-over';
}
function renderNotes(filterOwner) {
  const container=$('#notes');container.replaceChildren();
  const own=snapshot?.account?.id;
  const merged=notes.filter(n=>!Object.hasOwn(state.document.pending,n.sourceID)).concat(Object.values(state.document.pending).filter(Boolean).map(n=>({...n,ownerID:own,pending:true})),state.document.privateNotes.map(n=>({...n,private:true})));
  const visible=merged.filter(n=>!filterOwner||n.ownerID===filterOwner).sort((a,b)=>b.created-a.created);
  if(!visible.length)container.append(element('p','Your plaza is ready for its first note. Choose Write note, or connect a friend to see what they’re sharing.','empty'));
  for(const note of visible){
    const card=element('article',undefined,'note');const byline=element('div',undefined,'byline');byline.append(element('span',(note.author.name||'?').slice(0,1),'avatar-dot'),element('strong',note.author.name),element('span',note.private?'Private':note.pending?'Waiting to sync':'Plaza friends'));card.append(byline);
    if(note.topic)card.append(element('p',note.topic.label,'topic'));
    card.append(element('p',note.text,'body'));
    if(note.drawing.length){const canvas=element('canvas');canvas.width=600;canvas.height=240;canvas.setAttribute('role','img');canvas.setAttribute('aria-label',note.drawingDescription);renderDrawing(canvas,note.drawing);card.append(canvas,element('p',note.drawingDescription,'hint'));}
    const date=element('time',new Date(note.created*1000).toLocaleString());card.append(date);
    const actions=element('div',undefined,'actions');
    if(!note.private&&!note.pending&&state.connected)actions.append(button(`${note.liked?'♥':'♡'} ${note.likeCount||0}`,async()=>apply(await call('like',{id:note.id,liked:!note.liked}))));
    if(note.private||note.ownerID===own){actions.append(button('Edit',()=>openComposer(note)),button('Delete',async()=>{if(confirm('Delete this note and its shared discussion?'))apply(await call('deleteNote',note.sourceID||note.id));}));}
    card.append(actions);
    for(const reply of note.replies||[]){const row=element('div',undefined,'reply');row.append(element('strong',reply.author.name),element('p',reply.text));
      if(reply.ownerID===own)row.append(button('Edit reply',async()=>{const text=prompt('Edit reply',reply.text);if(text!==null)apply(await call('reply',{noteID:note.id,id:reply.id,text}));}));
      if(reply.ownerID===own||note.ownerID===own)row.append(button('Remove reply',async()=>{if(confirm('Remove this reply?'))apply(await call('reply',{noteID:note.id,id:reply.id,remove:true}));}));card.append(row);}
    if(!note.private&&!note.pending&&state.connected){const form=element('form',undefined,'reply-form');const input=element('input');input.placeholder='Leave a reply…';input.maxLength=560;input.required=true;input.setAttribute('aria-label','Reply to '+note.author.name);const send=element('button','Reply');send.type='submit';const replyID=crypto.randomUUID();form.append(input,send);form.addEventListener('submit',event=>{event.preventDefault();run(async()=>{send.disabled=true;try{apply(await call('reply',{noteID:note.id,id:replyID,text:input.value}));}finally{send.disabled=false;}});});card.append(form);}
    container.append(card);
  }
}
function renderFriends() {
  $('#requests').replaceChildren();$('#friend-list').replaceChildren();$('#blocks').replaceChildren();
  for(const request of snapshot?.incoming||[]){const row=element('div',undefined,'friend-row');row.append(element('strong',request.displayName),button('Accept',async()=>apply(await call('friend',{action:'accept',id:request.id}))),button('Decline',async()=>apply(await call('friend',{action:'remove',id:request.id}))));$('#requests').append(row);}
  for(const request of snapshot?.outgoing||[]){const row=element('div',undefined,'friend-row');row.append(element('strong',request.displayName),element('span','Request sent'),button('Cancel',async()=>apply(await call('friend',{action:'remove',id:request.id}))));$('#requests').append(row);}
  const friends=new Map([...(snapshot?.contacts||[]),...(snapshot?.friends||[]),...(snapshot?.unlinkedFriends||[])].map(f=>[f.id,f]));
  for(const friend of friends.values()){const row=element('div',undefined,'friend-row');row.append(element('strong',friend.displayName),button('Notes',()=>{view('journal');renderNotes(friend.id);status('Showing '+friend.displayName+'’s notes. Refresh to show everyone.');}),button('Remove',async()=>{if(confirm('Remove '+friend.displayName+'?'))apply(await call('friend',{action:'remove',id:friend.id}));}),button('Block',async()=>{if(confirm('Block '+friend.displayName+'?'))apply(await call('friend',{action:'block',id:friend.id}));}));$('#friend-list').append(row);}
  if(!friends.size)$('#friend-list').append(element('p','Add your first friend with a Plaza invitation.','empty'));
}
function loadMaker(){const a=state.document.avatar;$('#mii-name').value=a.name;$('#mii-outfit').value=a.outfit;$('#mii-skin').value=a.skin;$('#mii-hair-color').value=a.hairColor;$('#mii-hair').value=[0,33,60,80].includes(a.hair)?a.hair:33;$('#mii-height').value=a.height;$('#mii-build').value=a.build;$('#mii-glasses').checked=a.glasses;editingImportedHair=true;}
function openComposer(note) {
  editing=note||null;const draft=note||state.document.draft;drawing=structuredClone(draft.drawing||[]);
  $('#note-text').value=draft.text||'';$('#drawing-description').value=draft.drawingDescription||'';$('#visibility').value=note?(note.private?'private':'public'):(state.connected?'public':'private');
  $('#topic-label').value=draft.topic?.label||'';$('#steam-id').value=draft.topic?.steamAppID||'';$('#composer-title').textContent=note?'Edit your note':'Leave a little note';$('#composer-error').textContent='';
  $('#composer').showModal();renderDrawing($('#drawing'),drawing);updateCount();$('#note-text').focus();
}
function draft(){return{text:$('#note-text').value,drawing:structuredClone(drawing),drawingDescription:$('#drawing-description').value,topic:topic()};}
function topic(){const label=$('#topic-label').value.trim(),id=Number($('#steam-id').value);if(!label)return null;return{label,bundleID:id?`steam.app.${id}`:'org.squidproductions.plaza.topic',steamAppID:id||null};}
async function saveDraft(){if(!editing){const value=draft();await call('draft',value);state.document.draft=value;}}
function updateCount(){$('#count').textContent=`${[...$('#note-text').value].length} / 280`;}
for(const node of document.querySelectorAll('[data-view]'))node.addEventListener('click',()=>{view(node.dataset.view);if(node.dataset.view==='friends'&&state.connected)run(async()=>{const {blocks}=await call('blocks');for(const account of blocks){const row=element('div',undefined,'friend-row');row.append(element('strong',account.displayName),button('Unblock',async()=>{apply(await call('friend',{action:'unblock',id:account.id}));row.remove();}));$('#blocks').append(row);}});});
$('#write').addEventListener('click',()=>openComposer());$('#close-composer').addEventListener('click',()=>run(async()=>{await saveDraft();$('#composer').close();}));
$('#composer').addEventListener('cancel',event=>{event.preventDefault();run(async()=>{await saveDraft();$('#composer').close();});});
for(const id of ['note-text','drawing-description','topic-label','steam-id'])$('#'+id).addEventListener('input',()=>{updateCount();run(saveDraft);});
$('#eraser').addEventListener('click',()=>{erasing=!erasing;$('#eraser').setAttribute('aria-pressed',erasing);});
$('#clear-drawing').addEventListener('click',()=>{drawing=[];renderDrawing($('#drawing'),drawing);run(saveDraft);});
const canvas=$('#drawing');
function point(event){const r=canvas.getBoundingClientRect();return{x:Math.max(0,Math.min(1,(event.clientX-r.left)/r.width)),y:Math.max(0,Math.min(1,(event.clientY-r.top)/r.height))};}
canvas.addEventListener('pointerdown',event=>{if(drawing.length>=512)return;canvas.setPointerCapture(event.pointerId);stroke={eraser:erasing,points:[point(event)]};drawing.push(stroke);renderDrawing(canvas,drawing);});
canvas.addEventListener('pointermove',event=>{if(!stroke)return;if(drawing.reduce((n,s)=>n+s.points.length,0)>=20000)return;stroke.points.push(point(event));renderDrawing(canvas,drawing);});
for(const event of ['pointerup','pointercancel'])canvas.addEventListener(event,()=>{stroke=null;run(saveDraft);});
$('#discard-draft').addEventListener('click',()=>run(async()=>{await call('draft',{text:'',drawing:[],drawingDescription:''});state.document.draft={};$('#composer').close();}));
$('#note-form').addEventListener('submit',event=>{event.preventDefault();run(async()=>{
  const body=draft(),steam=body.topic?.steamAppID;if(steam&&(!Number.isInteger(steam)||steam<1||steam>4294967295))throw new Error('Enter a valid Steam App ID.');
  const note={...body,id:editing?.sourceID||editing?.id||crypto.randomUUID(),author:structuredClone(state.document.avatar),created:editing?.created||Date.now()/1000};
  $('#post-note').disabled=true;
  try{const value=await call('note',{note,visibility:$('#visibility').value});apply(value);$('#composer').close();status('Note saved.');}
  catch(error){$('#composer-error').textContent=error.message;await reloadLocal();if(Object.keys(state.document.pending).length){$('#composer').close();status('Note saved on this computer. It will sync when the service reconnects.');}}
  finally{$('#post-note').disabled=false;}
});});
async function reloadLocal(){const value=await call('state');apply(value);}
async function refresh(){if(refreshing)return;refreshing=true;try{apply(await call('refresh'));status('Plaza refreshed.');}finally{refreshing=false;}}
$('#refresh').addEventListener('click',()=>run(refresh));
$('#invite').addEventListener('click',()=>run(async()=>{$('#invite-result').value=(await call('invite')).code;status('Invitation created. It expires in 24 hours and can be used once.');}));
$('#copy-invite').addEventListener('click',()=>run(async()=>{await navigator.clipboard.writeText($('#invite-result').value);status('Invitation copied.');}));
$('#friend-request').addEventListener('submit',event=>{event.preventDefault();run(async()=>{apply(await call('friend',{action:'request',code:$('#friend-code').value.trim()}));$('#friend-code').value='';status('Request sent. Your friend can accept it in Plaza.');});});
$('#connect-form').addEventListener('submit',event=>{event.preventDefault();run(async()=>{await call('authStart',$('#service').value);$('#login-status').textContent='Finish signing in with Discord in your browser, then return here.';$('#connect').disabled=true;clearInterval(loginTimer);let attempts=0;loginTimer=setInterval(()=>run(async()=>{try{const value=await call('authFinish');if(!value.waiting){clearInterval(loginTimer);apply(value);$('#login-status').textContent='Connected. Open Friends to add your Mac or Windows friends.';}else if(++attempts>=50){clearInterval(loginTimer);$('#connect').disabled=false;$('#login-status').textContent='Sign-in expired. Connect Discord again.';}}catch(error){clearInterval(loginTimer);$('#connect').disabled=false;throw error;}}),6000);});});
$('#disconnect').addEventListener('click',()=>run(async()=>{clearInterval(loginTimer);apply(await call('logout'));$('#login-status').textContent='Disconnected. Your account’s saved notes remain on this computer.';}));
$('#maker-form').addEventListener('submit',event=>{event.preventDefault();run(async()=>{const a=structuredClone(state.document.avatar);Object.assign(a,{name:$('#mii-name').value.trim(),outfit:Number($('#mii-outfit').value),skin:Number($('#mii-skin').value),hairColor:Number($('#mii-hair-color').value),height:Number($('#mii-height').value),build:Number($('#mii-build').value),glasses:$('#mii-glasses').checked});if(!editingImportedHair)a.hair=Number($('#mii-hair').value);apply(await call('profile',a));status(state.connected?'Mii saved and shared with Plaza friends.':'Mii saved.');});});
let editingImportedHair=false;$('#mii-hair').addEventListener('change',()=>editingImportedHair=false);
$('#import-mii').addEventListener('click',()=>run(async()=>{const value=await call('importMii');if(value){apply(value);editingImportedHair=true;status('Character imported.');}}));
$('#export-mii').addEventListener('click',()=>run(()=>call('exportMii')));$('#website').addEventListener('click',()=>run(()=>call('website')));
$('#pause').addEventListener('click',()=>{const paused=plazaScene.pause();$('#pause').textContent=paused?'Resume motion':'Pause motion';$('#pause').setAttribute('aria-pressed',paused);});
let music;$('#music').addEventListener('click',()=>{if(music){music.close();music=null;$('#music').textContent='Music off';$('#music').setAttribute('aria-pressed','false');return;}music=new AudioContext();const gain=music.createGain();gain.gain.value=.018;gain.connect(music.destination);for(const frequency of[130.81,164.81,196,261.63]){const tone=music.createOscillator();tone.type='sine';tone.frequency.value=frequency;tone.connect(gain);tone.start();}$('#music').textContent='Music on';$('#music').setAttribute('aria-pressed','true');});
document.addEventListener('plaza-friend',event=>{view('journal');renderNotes(event.detail.id);status(event.detail.displayName+'’s notes.');});
const options=(selector,labels)=>labels.forEach((name,i)=>{const o=element('option',name);o.value=i;$(selector).append(o);});
options('#mii-outfit',['Red','Orange','Yellow','Lime','Green','Blue','Light blue','Pink','Purple','Brown','White','Black']);options('#mii-skin',['Peach','Light','Tan','Brown','Deep brown','Dark']);options('#mii-hair-color',['Black','Brown','Chestnut','Gold','Gray','Dark brown','Blond','Silver']);
run(async()=>{apply(await call('state'));if(state.connected)await refresh();});
setInterval(()=>{if(state?.connected&&!$('#composer').open&&!document.querySelector('input:focus,textarea:focus'))run(refresh);},15000);
