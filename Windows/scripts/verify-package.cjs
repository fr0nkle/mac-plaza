"use strict";
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..'),version=require('../package.json').version,dist=path.join(root,'dist');
const artifacts=[`Plaza-Windows-${version}-Setup-x64.exe`,`Plaza-Windows-${version}-x64.zip`,`Plaza-Windows-${version}-Source.zip`];
const native=path.join(dist,'win-unpacked/resources/native');
for(const name of ['PlazaEngine.exe','plaza_native.node','discord_partner_sdk.dll','swiftCore.dll','DISCORD-LICENSE-NOTICES.txt','RUNTIME-NOTICES.txt'])assert(fs.statSync(path.join(native,name)).isFile(),`Missing packaged runtime: ${name}`);
const pe=fs.readFileSync(path.join(dist,'win-unpacked/Plaza.exe'));assert.equal(pe.subarray(0,2).toString(),'MZ');assert.equal(pe.readUInt16LE(pe.readUInt32LE(60)+4),0x8664);
assert(!fs.existsSync(path.join(native,'Audio')),'Public preview must exclude local recordings');
const files={};for(const name of artifacts){const file=path.join(dist,name),bytes=fs.readFileSync(file);assert(bytes.length>1000,`Empty artifact: ${name}`);const sha256=crypto.createHash('sha256').update(bytes).digest('hex');fs.writeFileSync(file+'.sha256',sha256+'  '+name+'\n');files[name]={size:bytes.length,sha256,url:`https://github.com/fr0nkle/mac-plaza/releases/download/windows-v${version}/${name}`};}
fs.writeFileSync(path.join(dist,'windows-preview.json'),JSON.stringify({version,platform:'win32',arch:'x64',status:'untested',unsigned:true,macParityTarget:'0.23.0',files},null,2)+'\n');console.log('Verified x64 app, required native/runtime files, source, excluded recordings and checksums.');

const installer=artifacts[0],info=files[installer];
fs.writeFileSync(path.join(dist,'windows-update-candidate.json'),JSON.stringify({schema:1,channel:'preview',platform:'win32',arch:'x64',version,url:info.url,size:info.size,sha256:info.sha256,notes:fs.readFileSync(path.join(root,'TESTING.md'),'utf8')},null,2)+'\n');
console.log('Prepared unsigned preview metadata for the local signing/publication step.');
