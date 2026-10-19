'use strict';
window.PlazaMiiverse=(()=>{
  let bridge,state,index,snapshot,activity={activities:[],unreadCount:0},page='feed',community='all',order=[],birthdayID;
  const $=s=>document.querySelector(s),node=(tag,text,cls)=>{const n=document.createElement(tag);if(text!==undefined)n.textContent=text;if(cls)n.className=cls;return n;};
  const run=fn=>bridge.run(fn),button=(text,fn)=>{const b=node('button',text);b.type='button';b.onclick=()=>run(fn);return b;};
  function navigate(next,section='all'){
    if(page==='user')bridge.stopPreview();page=next;community=section;
    bridge.section(section);if(next==='communities'&&section==='all')reshuffle();
    paint();if(next==='notifications')run(bridge.loadActivity);
  }
  function reshuffle(){if(!index)return;order=PlazaCatalog.orderedCommunities(index,{history:state.history,apps:state.homeCatalog||state.apps,friends:snapshot?.friends||[]}).map(s=>s.id);}
  function icon(section){const art=node('span',undefined,'miiverse-community-icon');if(section.app?.icon){const img=node('img');img.alt='';img.src=section.app.icon;art.append(img);}else{art.textContent=section.id==='plaza'?'☼':section.label.slice(0,1);if(section.app)bridge.fillIcon(section.app,art);}return art;}
  function paint(){
    if(!state||!index)return;
    const feed=page==='feed'||(page==='communities'&&community!=='all');
    for(const id of ['user','communities','notifications'])$('#miiverse-'+id+'-page').hidden=page!==id||(id==='communities'&&feed);
    $('#miiverse-feed').hidden=!feed;$('#miiverse-page-title').textContent={user:'User Menu',feed:'Activity Feed',communities:'Communities',notifications:'Notifications'}[page];
    for(const b of document.querySelectorAll('[data-miiverse-page]')){b.classList.toggle('selected',b.dataset.miiversePage===page);b.setAttribute('aria-current',b.dataset.miiversePage===page?'page':'false');}
    $('#community-back').hidden=page!=='communities'||!feed;$('#miiverse-feed-title').textContent=community==='all'?'All Posts':index.sections.find(s=>s.id===community)?.label||'All Posts';
    $('#miiverse-signin').hidden=state.connected;$('#miiverse-primary-icon').replaceChildren(bridge.portrait(state.document.avatar));
    if(page==='user')paintUser();if(page==='communities'&&!feed)paintCommunities();paintActivity();
  }
  function paintCommunities(){
    const ranks=new Map(order.map((id,i)=>[id,i])),alphabetic=$('#community-sort').value==='name',query=$('#community-search').value.trim().toLocaleLowerCase();
    const sections=index.sections.filter(s=>!['all','mine','friends','public'].includes(s.id)).sort((a,b)=>a.id==='plaza'?-1:b.id==='plaza'?1:alphabetic?a.label.localeCompare(b.label,undefined,{numeric:true,sensitivity:'base'}):(ranks.get(a.id)??1e6)-(ranks.get(b.id)??1e6));
    $('#community-spotlight').replaceChildren(...sections.filter(s=>s.id!=='plaza').slice(0,innerWidth<900?3:5).map(s=>{const b=button('',()=>navigate('communities',s.id));b.title=s.label;b.setAttribute('aria-label','Open '+s.label+' community');b.append(icon(s));return b;}));
    const cards=sections.filter(s=>!query||s.label.toLocaleLowerCase().includes(query)).map(s=>{const b=button('',()=>navigate('communities',s.id));b.className='miiverse-community-card';b.setAttribute('aria-label',s.label+', '+s.count+' posts');b.dataset.community=s.id;const text=node('span');text.append(node('strong',s.label),node('small',s.count+' '+(s.count===1?'post':'posts')));b.append(icon(s),text,node('span','›'));return b;});
    $('#community-cards').replaceChildren(...cards);$('#community-empty').hidden=cards.length>0;
  }
  function paintUser(){
    $('#miiverse-account-portrait').replaceChildren(bridge.portrait(state.document.avatar));$('#miiverse-account-name').textContent=snapshot?.account?.displayName||state.document.avatar.name;
    $('#miiverse-account-status').textContent=state.connected?'Discord account linked':'Connect with Discord';$('#miiverse-account-message').textContent=state.connected?(state.serviceOnline?'Shared delivery online.':'Saved on this computer; shared delivery reconnects automatically.'):'Your private posts and drafts stay on this computer.';
    $('#miiverse-account-setup').textContent=state.connected?'Manage Discord Connection':'Set Up Discord';
    const alternate=state.music?.miiverseAlternate;$('#miiverse-alternate').disabled=!alternate;$('#miiverse-alternate').checked=!!state.document.settings?.miiverseAlternateTheme;
    $('#miiverse-alternate-name').textContent=alternate?alternate.name:'Choose a local audio file for the eShop (July 2014) alternate theme. Current music stays active until you apply it.';
    $('#miiverse-alternate-preview').hidden=!alternate;
    if(birthdayID!==state.document.avatar.id){birthdayID=state.document.avatar.id;$('#primary-birth-month').value=state.document.avatar.features.birthMonth||0;setDays(state.document.avatar.features.birthDay||0);$('#primary-birthday-status').textContent='';}
  }
  function setDays(day=0){const month=Number($('#primary-birth-month').value),count=month===2?29:[4,6,9,11].includes(month)?30:month?31:0;$('#primary-birth-day').replaceChildren(...Array.from({length:count+1},(_,i)=>{const o=node('option',i?String(i):'Unset');o.value=i;return o;}));$('#primary-birth-day').value=Math.min(day,count);$('#primary-birth-day').disabled=!month;validateBirthday();}
  function validateBirthday(){const month=Number($('#primary-birth-month').value),day=Number($('#primary-birth-day').value);$('#primary-birthday-save').disabled=!!state?.recoveryRequired||!(month===0&&day===0||month>0&&day>0);$('#primary-birthday-clear').disabled=!!state?.recoveryRequired;}
  function paintActivity(){
    const count=activity.unreadCount||0,label=count>99?'99+':String(count);for(const b of document.querySelectorAll('.miiverse-unread')){b.hidden=!count;b.textContent=label;}
    const button=$('[data-miiverse-page=notifications]');button.setAttribute('aria-label','Notifications, '+count+' unread');$('#miiverse-unread-count').textContent=count+' unread';$('#miiverse-mark-all').disabled=!count;
    const list=$('#miiverse-activity');list.replaceChildren();for(const e of activity.activities||[]){const row=buttonRow(e);list.append(row);}$('#miiverse-activity-empty').hidden=!!activity.activities?.length;
  }
  function buttonRow(entry){const row=button('',async()=>{activity=await bridge.call('activityRead',[entry.id]);bridge.activity(activity);navigate('feed');await bridge.openNote(entry.noteID);});row.className='activity-row'+(entry.read?'':' unread');row.setAttribute('aria-label',(entry.actorName||'A friend')+(entry.kind==='like'?' liked your note':' replied to your note')+(entry.read?', read':', unread'));
    if(entry.author)row.append(bridge.portrait(entry.author));const text=node('span');text.append(node('strong',entry.actorName||'A friend'),node('span',entry.kind==='like'?'Liked your note':entry.replyText||'Replied to your note'));row.append(text);if(!entry.read)row.append(node('span','●','unread-dot'));return row;}
  return{
    configure(value){bridge=value;for(const b of document.querySelectorAll('[data-miiverse-page]'))b.onclick=()=>run(()=>navigate(b.dataset.miiversePage));
      $('#miiverse-close').onclick=bridge.close;$('#community-back').onclick=()=>navigate('communities');$('#community-search').oninput=paintCommunities;$('#community-sort').onchange=()=>{if($('#community-sort').value!=='name')reshuffle();paintCommunities();};$('#community-shuffle').onclick=()=>{reshuffle();paintCommunities();};
      $('#miiverse-account-setup').onclick=()=>run(()=>bridge.call('panel',{kind:'settings',context:{category:'friends'}}));$('#miiverse-edit-mii').onclick=()=>run(()=>bridge.call('panel','maker'));
      $('#miiverse-alternate').onchange=()=>run(async()=>{bridge.stopPreview();bridge.apply(await bridge.call('settings',{miiverseAlternateTheme:$('#miiverse-alternate').checked}));});
      $('#miiverse-alternate-choose').onclick=()=>run(async()=>{if(await bridge.importMusic('miiverseAlternate'))bridge.apply(await bridge.call('settings',{miiverseAlternateTheme:true}));});
      $('#miiverse-alternate-preview').onclick=()=>run(()=>bridge.previewAlternate());
      const months=Array.from({length:13},(_,i)=>{const o=node('option',i?new Intl.DateTimeFormat(undefined,{month:'long'}).format(new Date(2024,i-1,1)):'Unset');o.value=i;return o;});$('#primary-birth-month').replaceChildren(...months);$('#primary-birth-month').onchange=()=>setDays(Number($('#primary-birth-day').value));$('#primary-birth-day').onchange=validateBirthday;
      for(const [id,clear]of [['primary-birthday-save',false],['primary-birthday-clear',true]])$('#'+id).onclick=()=>run(async()=>{const month=clear?0:Number($('#primary-birth-month').value),day=clear?0:Number($('#primary-birth-day').value);const next=await bridge.call('primaryBirthday',{month,day});birthdayID=null;bridge.apply(next);$('#primary-birthday-status').textContent=clear?'Birthday cleared.':'Birthday saved on this computer.';});
      $('#miiverse-mark-all').onclick=()=>run(async()=>{activity=await bridge.call('activityRead',(activity.activities||[]).filter(a=>!a.read).map(a=>a.id));bridge.activity(activity);paintActivity();});$('#miiverse-refresh-activity').onclick=()=>run(bridge.loadActivity);
      $('#miiverse-enable-notifications').onchange=()=>run(async()=>bridge.apply(await bridge.call('settings',{notifications:$('#miiverse-enable-notifications').checked})));
    },
    open(context={}){page=context.page==='notifications'?'notifications':'feed';community='all';birthdayID=null;reshuffle();paint();if(page==='notifications')run(bridge.loadActivity);},
    render(value){({state,index,snapshot}=value);activity=state.document.activityCache||value.activity||{activities:[],unreadCount:0};if(!order.length)reshuffle();$('#miiverse-enable-notifications').checked=!!state.document.settings?.notifications;paint();},
    activity(value){activity=value;paintActivity();},
    currentPage:()=>page
  };
})();
