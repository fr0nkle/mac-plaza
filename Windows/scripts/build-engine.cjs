const fs=require('node:fs'),path=require('node:path'),{spawnSync}=require('node:child_process');
const windows=path.resolve(__dirname,'..');
require('./prepare-shared.cjs');
const moduleCache=path.join(windows,'Engine/.build/module-cache');fs.mkdirSync(moduleCache,{recursive:true});
const result=spawnSync('swift',['build',...(process.platform==='darwin'?['--disable-sandbox']:[]),'-c','release','--package-path',path.join(windows,'Engine')],{stdio:'inherit',env:{...process.env,CLANG_MODULE_CACHE_PATH:process.env.CLANG_MODULE_CACHE_PATH||moduleCache,SWIFTPM_MODULECACHE_OVERRIDE:process.env.SWIFTPM_MODULECACHE_OVERRIDE||moduleCache}});if(result.status!==0)process.exit(result.status||1);
const output=path.join(windows,'native/runtime');fs.mkdirSync(output,{recursive:true});
const binary=path.join(windows,'Engine/.build/release',process.platform==='win32'?'PlazaEngine.exe':'PlazaEngine');fs.copyFileSync(binary,path.join(output,path.basename(binary)));
if(process.platform==='win32'){
  // Installed users do not need Swift. Ship the matching runtime, Foundation,
  // ICU and dispatch DLLs with the engine; never copy compiler/toolchain tools.
  const candidates=[process.env.SWIFT_RUNTIME,process.env.SDKROOT&&path.join(process.env.SDKROOT,'usr/bin'),process.env.SWIFT_PATH&&path.join(process.env.SWIFT_PATH,'../bin')].filter(Boolean);
  const base=path.join(process.env.SystemDrive||'C:','Library','Developer');
  function find(dir,depth=0){if(depth>11||!fs.existsSync(dir))return;for(const item of fs.readdirSync(dir,{withFileTypes:true})){const file=path.join(dir,item.name);if(item.isDirectory())find(file,depth+1);else if(item.name==='swiftCore.dll')candidates.push(dir);}}
  find(base);
  if(process.env.SDKROOT)find(process.env.SDKROOT);
  if(process.env.LOCALAPPDATA)find(path.join(process.env.LOCALAPPDATA,'Programs/Swift'));
  const runtime=candidates.find(dir=>{const file=path.join(dir,'swiftCore.dll');if(!fs.existsSync(file))return false;const bytes=fs.readFileSync(file);return bytes.length>64&&bytes.readUInt16LE(bytes.readUInt32LE(60)+4)===0x8664;});if(!runtime)throw new Error('Could not locate Swift runtime DLLs. Set SWIFT_RUNTIME.');
  for(const name of fs.readdirSync(runtime))if(name.toLowerCase().endsWith('.dll'))fs.copyFileSync(path.join(runtime,name),path.join(output,name));
  for(const name of ['vcruntime140.dll','vcruntime140_1.dll','msvcp140.dll','concrt140.dll']){const file=path.join(process.env.SystemRoot||'C:/Windows','System32',name);if(fs.existsSync(file))fs.copyFileSync(file,path.join(output,name));}
  fs.cpSync(path.join(windows,'native/RuntimeLicenses'),path.join(output,'RuntimeLicenses'),{recursive:true});
  fs.copyFileSync(path.join(windows,'native/RUNTIME-NOTICES.txt'),path.join(output,'RUNTIME-NOTICES.txt'));
  console.log('Bundled Swift runtime from '+runtime);
}
