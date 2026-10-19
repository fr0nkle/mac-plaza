'use strict';
// Run in a separate Node process so the installer starts only after Plaza exits cleanly.
const fs=require('node:fs/promises'),path=require('node:path'),{spawn}=require('node:child_process');
const {manifest,newer,verifyFile,PUBLIC_KEY}=require('./updates.cjs');
function installerEnvironment(source=process.env){const env={...source};delete env.ELECTRON_RUN_AS_NODE;delete env.NODE_OPTIONS;delete env.NODE_PATH;return env;}
function args(directory,relaunch){return['/S','--updated',...(relaunch?['--force-run']:[]),'/D='+directory];}
async function run(job,{key=PUBLIC_KEY,launch=(file,argv)=>spawn(file,argv,{detached:true,stdio:'ignore',windowsHide:true,env:installerEnvironment()}),alive=pid=>{try{process.kill(pid,0);return true;}catch(error){return error.code!=='ESRCH';}},sleep=ms=>new Promise(r=>setTimeout(r,ms))}={}){
  if(!Number.isSafeInteger(job.pid)||job.pid<=0||typeof job.installDirectory!=='string'||!path.isAbsolute(job.installDirectory)||typeof job.directory!=='string'||!path.isAbsolute(job.directory))throw Error('Invalid installation request.');
  const info=manifest(JSON.parse(await fs.readFile(path.join(job.directory,'pending.json'),'utf8')),key);if(!newer(info.version,job.current))throw Error('Refusing an old update.');
  for(let i=0;alive(job.pid);i++){if(i>=120)throw Error('Plaza did not close. The update was not installed.');await sleep(500);}
  // Recheck the signed digest immediately before executing the installer.
  const installer=path.join(job.directory,'installer.exe');await verifyFile(installer,info);
  const child=launch(installer,args(job.installDirectory,job.relaunch));await new Promise((resolve,reject)=>{child.once('spawn',resolve);child.once('error',reject);});child.unref();
}
if(require.main===module){let job;try{job=JSON.parse(process.argv[2]);}catch{process.exitCode=1;}if(job)run(job).catch(async()=>{await fs.writeFile(path.join(job.directory,'install-error.txt'),'The update could not be installed. Reopen Plaza and retry.').catch(()=>{});process.exitCode=1;});}
module.exports={run,args,installerEnvironment};
