'use strict';
// One bounded retry cache: reuse only this task's immutable, validated engine.
const fs=require('node:fs'),cp=require('node:child_process');
const run='39195951766',commit='75fb24b259e812c89ef12d24f41c3f7e477c36dd';
const inputs=['Sources','Tests','Windows/Engine','Windows/scripts/build-engine.cjs','Windows/scripts/prepare-shared.cjs','Windows/scripts/prepare-artwork.cjs','Windows/scripts/test-shared.cjs','Windows/native/RuntimeLicenses','Windows/native/RUNTIME-NOTICES.txt'];
function api(route){return JSON.parse(cp.execFileSync(process.env.PLAZA_GH||'gh',['api',route],{encoding:'utf8'}));}
let reuse=false;
try{
 const yaml=fs.readFileSync('../.github/workflows/windows.yml','utf8');
 if(!yaml.includes('swift-version: swift-6.4.1-release'))throw Error('Toolchain changed.');
 cp.execFileSync('git',['-C','..','diff','--exit-code',commit,'HEAD','--',...inputs],{stdio:'pipe'});
 const r=api('repos/fr0nkle/mac-plaza/actions/runs/'+run);
 const jobs=api('repos/fr0nkle/mac-plaza/actions/runs/'+run+'/jobs?per_page=100').jobs;
 const artifacts=api('repos/fr0nkle/mac-plaza/actions/runs/'+run+'/artifacts').artifacts;
 if(r.head_sha!==commit||r.repository.full_name!=='fr0nkle/mac-plaza'||!jobs.some(j=>j.name==='contracts'&&j.conclusion==='success')||!artifacts.some(a=>a.name==='windows-shared-runtime'&&!a.expired))throw Error('Validated artifact unavailable.');
 reuse=true;console.log('Reuse unchanged Windows engine/runtime and shared Swift test evidence from validated contracts at '+commit+'. JavaScript, HTTP contracts, backend and installed update tests run again.');
}catch{console.log('Build and test the shared Swift engine normally.');}
fs.appendFileSync(process.env.GITHUB_OUTPUT,'reuse='+reuse+'\n');
