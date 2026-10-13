const fs=require('node:fs'),path=require('node:path'),{spawnSync}=require('node:child_process');
const windows=path.resolve(__dirname,'..');
require('./prepare-shared.cjs');
const result=spawnSync('swift',['build','-c','release','--package-path',path.join(windows,'Engine')],{stdio:'inherit'});if(result.status!==0)process.exit(result.status||1);
const output=path.join(windows,'native/runtime');fs.mkdirSync(output,{recursive:true});
const binary=path.join(windows,'Engine/.build/release',process.platform==='win32'?'PlazaEngine.exe':'PlazaEngine');fs.copyFileSync(binary,path.join(output,path.basename(binary)));
if(process.platform==='win32'){
  // Installed users do not need Swift. Ship the matching runtime, Foundation,
  // ICU and dispatch DLLs with the engine; never copy compiler/toolchain tools.
  const candidates=[process.env.SWIFT_RUNTIME,process.env.SDKROOT&&path.join(process.env.SDKROOT,'usr/bin'),process.env.SWIFT_PATH&&path.join(process.env.SWIFT_PATH,'../bin')].filter(Boolean);
  const base=path.join(process.env.SystemDrive||'C:','Library','Developer');
  function find(dir,depth=0){if(depth>11||!fs.existsSync(dir))return;for(const item of fs.readdirSync(dir,{withFileTypes:true})){const file=path.join(dir,item.name);if(item.isDirectory())find(file,depth+1);else if(item.name==='swiftCore.dll')candidates.push(dir);}}
  find(base);
  const runtime=candidates.find(dir=>fs.existsSync(path.join(dir,'swiftCore.dll')));if(!runtime)throw new Error('Could not locate Swift runtime DLLs. Set SWIFT_RUNTIME.');
  for(const name of fs.readdirSync(runtime))if(name.toLowerCase().endsWith('.dll'))fs.copyFileSync(path.join(runtime,name),path.join(output,name));
  console.log('Bundled Swift runtime from '+runtime);
}
