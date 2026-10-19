'use strict';
// Complete one explicit preview release on the existing signing Mac. No key export.
const fs=require('node:fs/promises'),path=require('node:path'),os=require('node:os'),crypto=require('node:crypto'),{spawnSync}=require('node:child_process');
const {manifest,newer}=require('../src/updates.cjs');
const SITE='appgprj_6acdbb93b0ec819189849d03b4b1e683';
function releaseInfo(release,candidate){
 if(!/^\d{1,6}\.\d{1,6}\.\d{1,6}$/.test(candidate.version))throw Error('Invalid preview version.');
 if(release.draft!==false||release.prerelease!==true||release.tag_name!=='windows-v'+candidate.version)throw Error('Choose a published Windows preview release.');
 const names=[`Plaza-Windows-${candidate.version}-Setup-x64.exe`,`Plaza-Windows-${candidate.version}-x64.zip`,`Plaza-Windows-${candidate.version}-Source.zip`];
 const origin='https://github.com/fr0nkle/mac-plaza/releases/download/'+release.tag_name+'/';
 for(const name of names){const a=release.assets?.find(a=>a.name===name);if(!a||a.state!=='uploaded'||a.browser_download_url!==origin+name||!Number.isSafeInteger(a.size)||a.size<1000||!/^sha256:[a-f0-9]{64}$/.test(a.digest))throw Error('Missing or invalid published preview asset: '+name);}
 const a=release.assets.find(a=>a.name===names[0]);if(candidate.schema!==1||candidate.channel!=='preview'||candidate.platform!=='win32'||candidate.arch!=='x64'||candidate.url!==a.browser_download_url||candidate.sha256!==a.digest.slice(7)||candidate.size!==a.size||typeof candidate.notes!=='string'||candidate.notes.length>8000||!candidate.notes.includes('UNTESTED'))throw Error('The update candidate does not match the published untested preview.');
 return names.map(name=>release.assets.find(a=>a.name===name));
}
function advance(previous,next){if(previous&&(!newer(next.version,previous.version))&&(next.version!==previous.version||next.sha256!==previous.sha256))throw Error('Refusing an older, reused or replaced preview version.');}
async function prepare({assets,releaseFile,site,signer}){
 const release=JSON.parse(await fs.readFile(releaseFile,'utf8')),candidate=JSON.parse(await fs.readFile(path.join(assets,'windows-update-candidate.json'),'utf8')),published=releaseInfo(release,candidate);
 for(const a of published){const bytes=await fs.readFile(path.join(assets,a.name));if(bytes.length!==a.size||crypto.createHash('sha256').update(bytes).digest('hex')!==a.digest.slice(7))throw Error('Downloaded asset checksum mismatch: '+a.name);}
 const config=JSON.parse(await fs.readFile(path.join(site,'.openai/hosting.json'),'utf8'));if(config.project_id!==SITE||config.static?.directory!=='dist')throw Error('Use the existing Plaza Site checkout.');
 const feed=path.join(site,'dist/windows-preview-update.json');let previous=null;try{previous=manifest(JSON.parse(await fs.readFile(feed,'utf8')));}catch(error){if(error.code!=='ENOENT')throw error;}advance(previous,candidate);
 const temporary=await fs.mkdtemp(path.join(os.tmpdir(),'plaza-preview-sign-'));let envelope;
 try{const input=path.join(temporary,'preview-metadata.bin'),bytes=Buffer.from(JSON.stringify(candidate));await fs.writeFile(input,bytes,{mode:0o600});
  const result=spawnSync(signer,['--account','macplaza-updates','-p',input],{encoding:'utf8'});if(result.status!==0)throw Error('The existing local signing key is unavailable. No signing credential was created or exported.');
  envelope={payload:bytes.toString('base64'),signature:result.stdout.trim()};manifest(envelope); // Pin verification to the exact key shipped in the app.
 }finally{await fs.rm(temporary,{recursive:true,force:true});}
 const output=JSON.stringify(envelope,null,2)+'\n';await fs.writeFile(feed+'.tmp',output);await fs.rename(feed+'.tmp',feed);
 const attachment=path.join(assets,'windows-preview-update.json');await fs.writeFile(attachment,output);
 return {version:candidate.version,channel:'preview',feed,attachment,siteProjectID:SITE,feedURL:'https://plaza.squidproductions.org/windows-preview-update.json',status:'signed; publish the Site to deliver',installerSHA256:candidate.sha256};
}
if(require.main===module){const args=process.argv.slice(2),options={};for(let i=0;i<args.length;i+=2){if(!['--assets','--release','--site','--signer'].includes(args[i])||!args[i+1])throw Error('Usage: node scripts/publish-update.cjs --assets DIR --release RELEASE.json --site SITE_CHECKOUT --signer EXISTING_SPARKLE_SIGNER');options[{'--assets':'assets','--release':'releaseFile','--site':'site','--signer':'signer'}[args[i]]]=path.resolve(args[i+1]);}if(Object.keys(options).length!==4)throw Error('All release, asset, site and existing signer arguments are required.');prepare(options).then(r=>console.log(JSON.stringify(r,null,2))).catch(e=>{console.error(e.message);process.exitCode=1;});}
module.exports={releaseInfo,advance,prepare};
