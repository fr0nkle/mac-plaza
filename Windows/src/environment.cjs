'use strict';
// Core Audio calls can wait on Windows audio services. Keep them in a
// disposable utility process so the plaza and quit controls remain responsive.
const native=require(process.argv[2]);
const owner=Number(process.argv[3]);
const path=require('node:path'),{spawn}=require('node:child_process'),{createGate}=require('./music-interruption.cjs');
const gate=createGate();let observation=null,observedAt=0,worker=null,retryAt=0,startedAt=0;
function startMusicProbe(){
  const executable=path.join(path.dirname(process.argv[2]),'PlazaMusicProbe.exe');
  const child=spawn(executable,[String(process.pid)],{windowsHide:true,stdio:['ignore','pipe','ignore']});
  worker=child;startedAt=Date.now();let buffer='';
  child.stdout.on('data',chunk=>{buffer+=chunk;if(buffer.length>262144){child.kill();return;}let end;while((end=buffer.indexOf('\n'))>=0){const line=buffer.slice(0,end);buffer=buffer.slice(end+1);try{const value=JSON.parse(line);if(typeof value.available==='boolean'&&Array.isArray(value.media)&&Array.isArray(value.audio)){observation=value;observedAt=Date.now();}}catch{}}});
  const ended=()=>{if(worker===child){worker=null;observation=null;retryAt=Date.now()+30000;}};
  child.on('error',ended);child.on('exit',ended);
}
function sample(){try{
  if(worker&&Date.now()-Math.max(startedAt,observedAt)>5000)worker.kill();
  if(!worker&&Date.now()>=retryAt)startMusicProbe();
  const value=JSON.parse(native.environment(owner));
  // Legacy native otherAudio includes microphones and arbitrary peaks. Never use
  // it to interrupt music; fail open if the positive music probe is unavailable.
  delete value.otherAudio;
  const fresh=Date.now()-observedAt<1000;
  value.otherMusic=gate(fresh?observation:null,Date.now());
  value.musicProbeAvailable=fresh&&observation?.available===true;
  process.parentPort.postMessage(JSON.stringify(value));
}catch{}}
process.on('exit',()=>worker?.kill());
sample();setInterval(sample,500);
