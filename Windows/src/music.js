'use strict';
// One mixer in the plaza window also serves wallpaper companion windows.
// Each role has its own volume; the plaza loop retains its playhead.
window.PlazaMusic=(()=>{
  const companion=new URLSearchParams(location.search).has('panel');
  const keys={plaza:'musicVolume',maker:'makerMusicVolume',friends:'friendsMusicVolume',settings:'settingsMusicVolume',writing:'writingMusicVolume'};
  let state,role='plaza',muted=false,context,loop,revision='',current=null,serial=Promise.resolve();
  const voices=new Map();
  async function sound(){if(loop)return loop;const value=await window.plaza.call('engine',{command:'music',args:{}});const bytes=Uint8Array.from(atob(value.data),c=>c.charCodeAt(0));loop=URL.createObjectURL(new Blob([bytes],{type:'audio/wav'}));return loop;}
  async function updateVoice(){if(companion||!state)return;const enabled=state.document.settings?.ambientSound&&!muted;const volume=Math.min(.35,Math.max(0,state.document.settings?.[keys[role]]??.12));
    if(!enabled){for(const voice of voices.values()){voice.audio.pause();voice.gain.gain.cancelScheduledValues(context.currentTime);voice.gain.gain.value=0;}return;}
    context ||= new AudioContext();await context.resume();const source=state.music?.[role]?.file||'fallback';const key=role+':'+source;let voice=voices.get(key);
    if(!voice){const audio=new Audio();audio.loop=true;audio.src=source==='fallback'?await sound():'plaza-media://music/'+role+'?revision='+encodeURIComponent(source);const gain=context.createGain();gain.gain.value=0;context.createMediaElementSource(audio).connect(gain).connect(context.destination);voice={audio,gain,timer:null};voices.set(key,voice);}
    clearTimeout(voice.timer);voice.timer=null;
    if(current&&current!==voice){const old=current;old.gain.gain.cancelScheduledValues(context.currentTime);old.gain.gain.setValueAtTime(old.gain.gain.value,context.currentTime);old.gain.gain.linearRampToValueAtTime(0,context.currentTime+1.2);old.timer=setTimeout(()=>{old.audio.pause();old.timer=null;},1250);}
    const changed=current!==voice||voice.audio.paused;current=voice;await voice.audio.play();const gain=voice.gain.gain;gain.cancelScheduledValues(context.currentTime);gain.setValueAtTime(gain.value,context.currentTime);gain.linearRampToValueAtTime(volume,context.currentTime+(changed?1.2:.2));
  }
  function schedule(){serial=serial.catch(()=>{}).then(updateVoice).catch(error=>document.dispatchEvent(new CustomEvent('plaza-ui-error',{detail:'Music could not play: '+error.message})));return serial;}
  function setRole(next){if(!keys[next])next='plaza';if(companion){window.plaza.call('musicRole',next).catch(()=>{});return;}if(role!==next){role=next;schedule();}}
  if(!companion)window.plaza.subscribe('plaza-music-role',setRole);
  return{role:setRole,update(value){state=value;const next=JSON.stringify([value.music,value.document.settings]);if(next!==revision){revision=next;schedule();}},mute(value){if(muted!==value){muted=value;schedule();}},diagnostics:()=>({role,muted,voices:[...voices].map(([key,v])=>({key,playing:!v.audio.paused,time:v.audio.currentTime,volume:v.gain.gain.value}))})};
})();
