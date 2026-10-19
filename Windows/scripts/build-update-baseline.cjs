'use strict';
// CI only: embed a disposable signing public key in the older test baseline.
// The real release is built first, with the production key. Always restore source.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),{spawnSync}=require('node:child_process');
const source=path.resolve('src/updates.cjs'),original=fs.readFileSync(source,'utf8'),pair=crypto.generateKeyPairSync('ed25519');
const key=pair.publicKey.export({format:'der',type:'spki'}).subarray(-32).toString('base64');
fs.mkdirSync('update-baseline',{recursive:true});fs.writeFileSync('update-baseline/test-key.json',JSON.stringify({publicKey:key,privateKey:pair.privateKey.export({format:'pem',type:'pkcs8'})}));
try{fs.writeFileSync(source,original.replace("const PUBLIC_KEY='nb75UIGtfJC3VgrIPHOZWMKdZoo9l8ZpQUqenSJgGXE=';",`const PUBLIC_KEY='${key}';`));
 const result=spawnSync(process.execPath,[require.resolve('electron-builder/out/cli/cli.js'),'--win','nsis','--x64','--publish','never','--config.extraMetadata.version=0.3.99','--config.directories.output=update-baseline','--config.nsis.artifactName=Plaza-Update-Baseline.exe'],{stdio:'inherit'});if(result.error)throw result.error;process.exitCode=result.status||0;
}finally{fs.writeFileSync(source,original);}
