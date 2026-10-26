'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {hasOtherMusic,createGate,muteMusic}=require('../src/music-interruption.cjs');
const sample=()=>({available:true,media:[{appId:'Player.exe',status:'Playing',type:'Music'}],audio:[{process:'player.exe',appId:'',active:true,muted:false,peak:.05}]});
test('only a matched playing music session with audible render output interrupts',()=>{
 assert.equal(hasOtherMusic(sample()),true);
 for(const edit of [s=>s.media=[],s=>s.audio=[],s=>s.available=false,s=>s.media[0].status='Paused',s=>s.media[0].status='Stopped',s=>s.media[0].type='Video',s=>s.media[0].type='Unknown',s=>s.audio[0].peak=0,s=>s.audio[0].muted=true,s=>s.audio[0].active=false,s=>s.audio[0].process='notification.exe']){const s=sample();edit(s);assert.equal(hasOtherMusic(s),false);}
 assert.equal(hasOtherMusic(null),false);
});
test('idle, microphone and notification observations do not imply music',()=>{
 for(const s of [{available:true,media:[],audio:[]},{available:true,media:[],audio:sample().audio,otherAudio:true},{available:true,media:[],audio:[],capture:[{active:true}]}])assert.equal(hasOtherMusic(s),false);
 assert.equal(muteMusic({covered:true,visibleWindow:false,otherAudio:true}),false);
});
test('own and duplicate Plaza sessions are ignored; packaged player identity matches',()=>{
 for(const id of ['Plaza.exe','Windows Plaza.exe','plaza-windows','org.squidproductions.plaza.windows']){const s=sample();s.media[0].appId=id;s.audio[0].process=id;assert.equal(hasOtherMusic(s),false);}
 const s=sample();s.media[0].appId='Vendor.Player_abc!App';s.audio[0].appId='vendor.player_abc!app';assert.equal(hasOtherMusic(s),true);
});
test('requires sustained music, resumes on stop/silence/unavailability, resets onset',()=>{
 const gate=createGate();const s=sample();assert.equal(gate(s,0),false);assert.equal(gate(s,1000),false);assert.equal(gate(s,1500),true);
 s.media[0].status='Paused';assert.equal(gate(s,2000),false);s.media[0].status='Playing';assert.equal(gate(s,2500),false);assert.equal(gate(s,4000),true);
 assert.equal(gate(null,4500),false);assert.equal(gate(s,5000),false);
});
test('lock and suspend still protect lifecycle; desktop appearance does not mute',()=>{
 assert.equal(muteMusic({otherMusic:true}),true);assert.equal(muteMusic({locked:true}),true);assert.equal(muteMusic({suspended:true}),true);assert.equal(muteMusic({}),false);
});
