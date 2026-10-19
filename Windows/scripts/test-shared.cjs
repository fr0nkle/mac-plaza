const fs=require('node:fs'),path=require('node:path'),{spawnSync}=require('node:child_process');
require('./prepare-shared.cjs');
const windows=path.resolve(__dirname,'..'),moduleCache=path.join(windows,'Engine/.build/module-cache');fs.mkdirSync(moduleCache,{recursive:true});
const result=spawnSync('swift',['test',...(process.platform==='darwin'?['--disable-sandbox']:[]),'-c','release','--package-path',path.join(windows,'Engine')],{stdio:'inherit',env:{...process.env,CLANG_MODULE_CACHE_PATH:process.env.CLANG_MODULE_CACHE_PATH||moduleCache,SWIFTPM_MODULECACHE_OVERRIDE:process.env.SWIFTPM_MODULECACHE_OVERRIDE||moduleCache}});
if(result.error)console.error(result.error.message);
process.exit(result.status??1);
