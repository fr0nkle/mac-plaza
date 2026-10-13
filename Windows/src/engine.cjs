'use strict';
const {spawn}=require('node:child_process');
const path=require('node:path'),fs=require('node:fs');
class Engine {
  constructor(packaged){
    const binary=packaged?path.join(process.resourcesPath,'native','PlazaEngine.exe'):path.join(__dirname,'../Engine/.build/release',process.platform==='win32'?'PlazaEngine.exe':'PlazaEngine');
    if(!fs.existsSync(binary))throw new Error('The shared Plaza engine is missing. Reinstall this build.');
    this.child=spawn(binary,[],{stdio:['pipe','pipe','pipe'],windowsHide:true});this.next=0;this.pending=new Map();let buffer='';
    this.child.stdout.on('data',chunk=>{buffer+=chunk;if(buffer.length>8_000_000){this.close();return;}let end;while((end=buffer.indexOf('\n'))>=0){const line=buffer.slice(0,end);buffer=buffer.slice(end+1);try{const value=JSON.parse(line),pending=this.pending.get(value.id);if(pending){clearTimeout(pending.timer);this.pending.delete(value.id);value.ok?pending.resolve(value.value):pending.reject(new Error(value.error));}}catch{this.close();}}});
    this.child.on('error',()=>this.close());this.child.on('exit',()=>this.close());this.child.stderr.on('data',()=>{});
  }
  call(command,args={}){return new Promise((resolve,reject)=>{const id=++this.next,timer=setTimeout(()=>{this.pending.delete(id);reject(new Error('The Plaza engine did not respond.'));},20000);this.pending.set(id,{resolve,reject,timer});this.child.stdin.write(JSON.stringify({id,command,args})+'\n',error=>{if(error){clearTimeout(timer);this.pending.delete(id);reject(new Error('The Plaza engine stopped.'));}});});}
  close(){for(const p of this.pending.values()){clearTimeout(p.timer);p.reject(new Error('The Plaza engine stopped.'));}this.pending.clear();this.child.kill();}
}
module.exports={Engine};
