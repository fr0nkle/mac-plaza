'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const source=fs.readFileSync(path.join(__dirname,'../src/music.js'),'utf8');
function fixture(search=''){
  const audio=[],timers=new Map(),errors=[],calls=[];let next=0;
  class Audio{constructor(){this.paused=true;this.currentTime=0;audio.push(this);}async play(){this.paused=false;}pause(){this.paused=true;}removeAttribute(){this.src='';}load(){}}
  class AudioContext{constructor(){this.currentTime=0;this.destination={};this.state='running';}async resume(){}async close(){this.state='closed';}createGain(){const gain={value:0,cancelScheduledValues(){},setValueAtTime(v){this.value=v;},linearRampToValueAtTime(v){this.value=v;}};return{gain,connect(){},disconnect(){}};}createMediaElementSource(){return{connect:g=>g};}}
  const context=vm.createContext({window:{plaza:{call:async(...args)=>{calls.push(args);return{};},subscribe(){}}},location:{search},URLSearchParams,Audio,AudioContext,setTimeout:fn=>{timers.set(++next,fn);return next;},clearTimeout:id=>timers.delete(id),document:{dispatchEvent:e=>errors.push(e.detail)},CustomEvent:class{constructor(_,o){this.detail=o.detail;}}});
  vm.runInContext(source,context);
  return{music:context.window.PlazaMusic,audio,errors,calls,async settle(){await new Promise(setImmediate);},fade(){for(const [id,fn]of timers){timers.delete(id);fn();}}};
}
test('all seven local music roles select their own source and volume; crossfades preserve plaza playhead',async()=>{
  const f=fixture(),roles=['plaza','maker','friends','settings','writing','miiverse','miiverseAlternate'];
  const state={document:{settings:{ambientSound:true}},music:Object.fromEntries(roles.map(r=>[r,{file:`C:\\Synthetic Music\\${r}.wav`}]))};
  f.music.update(state);await f.settle();f.audio[0].currentTime=42;
  for(const role of roles.slice(1)){f.music.role(role);await f.settle();f.fade();const playing=f.music.diagnostics().voices.filter(v=>v.playing);assert.equal(playing.length,1);assert(playing[0].key.startsWith(role+':'));assert.equal(playing[0].volume,.10);}
  f.music.role('plaza');await f.settle();f.fade();assert.equal(f.audio[0].currentTime,42);assert.equal(f.music.diagnostics().voices.find(v=>v.playing).volume,.12);
  state.document.settings.miiverseAlternateTheme=true;f.music.update(state);f.music.role('miiverse');await f.settle();f.fade();assert.equal(f.music.diagnostics().track,'miiverseAlternate');
  assert.deepEqual(f.errors,[]);await f.music.shutdown();assert(f.audio.every(a=>a.paused));
});
test('environment mute and list mode pause plaza without disabling companion music',async()=>{
  const f=fixture();f.music.update({document:{settings:{ambientSound:true}},music:{plaza:{file:'plaza.wav'},friends:{file:'friends.wav'}}});await f.settle();
  f.music.mute(true);await f.settle();assert(f.audio.every(a=>a.paused));
  f.music.mute(false);await f.settle();assert.equal(f.audio[0].paused,false);
  f.music.list(true);await f.settle();assert.equal(f.audio[0].paused,true);
  f.music.role('friends');await f.settle();f.fade();assert.equal(f.music.diagnostics().voices.filter(v=>v.playing).length,1);
  assert.deepEqual(f.errors,[]);await f.music.shutdown();
});
test('companion window delegates role without starting another audio mixer',async()=>{
  const f=fixture('?panel=maker');f.music.role('maker');await f.settle();assert.deepEqual(f.calls,[['musicRole','maker']]);assert.equal(f.audio.length,0);
});

test('stopping other music preserves the user manual music-off preference',async()=>{
 const f=fixture(),state={document:{settings:{ambientSound:true}},music:{plaza:{file:'plaza.wav'}}};
 f.music.update(state);await f.settle();assert.equal(f.audio[0].paused,false);
 f.audio[0].currentTime=33;f.music.mute(true);await f.settle();
 state.document.settings.ambientSound=false;f.music.update(state);await f.settle();
 f.music.mute(false);await f.settle();assert(f.audio.every(a=>a.paused));assert.equal(f.audio[0].currentTime,33);
 state.document.settings.ambientSound=true;f.music.update(state);await f.settle();assert.equal(f.audio[0].paused,false);assert.equal(f.audio[0].currentTime,33);
 await f.music.shutdown();
});
