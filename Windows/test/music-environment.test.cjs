'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),vm=require('node:vm'),fs=require('node:fs'),path=require('node:path'),{EventEmitter}=require('node:events');
test('denied music helper fails open despite legacy capture/audio and window coverage',()=>{
 const children=[],messages=[],callbacks=[];
 const process={argv:['node','environment.cjs','C:/native/plaza_native.node','123'],pid:456,parentPort:{postMessage:v=>messages.push(JSON.parse(v))},on(){}};
 const sandbox={process,Date,JSON,setInterval:fn=>callbacks.push(fn),require:id=>{
  if(id===process.argv[2])return{environment:()=>JSON.stringify({otherAudio:true,covered:true,foreground:''})};
  if(id==='node:path')return path;
  if(id==='node:child_process')return{spawn:()=>{const child=new EventEmitter();child.stdout=new EventEmitter();child.kill=()=>{};children.push(child);return child;}};
  if(id==='./music-interruption.cjs')return require('../src/music-interruption.cjs');throw Error(id);
 }};
 vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../src/environment.cjs'),'utf8'),sandbox);
 children[0].emit('error',new Error('Application Control blocked helper'));callbacks[0]();
 assert.equal(children.length,1);assert.equal(messages.length,2);
 for(const m of messages){assert.equal(m.otherMusic,false);assert.equal(m.musicProbeAvailable,false);assert.equal(m.otherAudio,undefined);}
});
