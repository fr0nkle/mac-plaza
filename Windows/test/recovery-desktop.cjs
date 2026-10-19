'use strict';
const {_electron:electron}=require('playwright'),assert=require('node:assert/strict'),fs=require('node:fs/promises'),path=require('node:path'),os=require('node:os');
const core=require('../src/core.cjs');
(async()=>{
  const root=path.resolve(__dirname,'..'),directory=await fs.mkdtemp(path.join(os.tmpdir(),'plaza-recovery-')),doc=core.document();let app;
  doc.avatars=[doc.avatar];doc.draft.text='Recover this draft';doc.settings={safeMode:true,population:20,ambientSound:true};
  const good={audienceVersion:1,origin:core.DEFAULT_SERVICE,accounts:{offline:doc}},bad=structuredClone(good);bad.accounts.offline.avatar.name='';
  const original=JSON.stringify(bad);await fs.writeFile(path.join(directory,'plaza.json'),original);await fs.writeFile(path.join(directory,'plaza.json.backup'),JSON.stringify(good));
  try{
    app=await electron.launch({...(process.env.PLAZA_EXECUTABLE?{executablePath:process.env.PLAZA_EXECUTABLE}:{}),args:[...(process.env.PLAZA_EXECUTABLE?[]:[root]),'--user-data-dir='+directory],timeout:60000});const page=await app.firstWindow(),errors=[];page.on('pageerror',e=>errors.push(e.message));
    await page.waitForFunction(async()=>!!window.plaza&&(await plaza.call('state')).recoveryRequired);
    assert.equal(await fs.readFile(path.join(directory,'plaza.json'),'utf8'),original);
    await assert.rejects(page.evaluate(()=>plaza.call('settings',{population:40})),/Restore a backup/);
    await page.evaluate(()=>plaza.call('recoverBackup'));await page.waitForFunction(async()=>(await plaza.call('state')).document.draft.text==='Recover this draft');
    assert.equal((await page.evaluate(()=>plaza.call('state'))).recoveryRequired,false);assert.equal(await page.evaluate(()=>plazaScene.surface()),null);
    const preserved=(await fs.readdir(directory)).find(f=>f.startsWith('plaza.json.unreadable-'));assert(preserved);assert.equal(await fs.readFile(path.join(directory,preserved),'utf8'),original);
    await page.evaluate(()=>PlazaUISounds.play('uiClick',true));assert.equal(await page.evaluate(()=>PlazaUISounds.diagnostics().playedCount),0);
    await assert.rejects(page.evaluate(()=>plaza.call('exportPortrait','data:image/png;base64,aGVsbG8=')),/safe mode/);
    await page.evaluate(()=>plaza.call('settings',{safeMode:false}));await page.waitForFunction(()=>document.body.dataset.sceneReady==='true');assert(await page.evaluate(()=>!!plazaScene.surface()));
    await page.emulateMedia({reducedMotion:'reduce'});await page.evaluate(()=>plaza.call('engine',{command:'finishEntrance',args:{}}));
    const before=await page.evaluate(async()=>JSON.stringify((await plaza.frame({dt:0,pauseMotion:true})).poses));await page.waitForTimeout(300);
    assert.equal(await page.evaluate(async()=>JSON.stringify((await plaza.frame({dt:0,pauseMotion:true})).poses)),before,'System reduced motion freezes the crowd');
    await page.evaluate(()=>plaza.call('settings',{safeMode:true}));await page.waitForFunction(()=>!plazaScene.surface());await page.waitForFunction(()=>PlazaMusic.diagnostics().voices.every(v=>!v.playing));
    const setUpdate=async(phase,version)=>app.evaluate(({app},{phase,version})=>{const req=process.getBuiltinModule('module').createRequire(app.getAppPath()+'/package.json'),u=req(app.getAppPath()+'/src/main.cjs').getUpdater();u.info=version?{version}:null;u.set(phase,'Local UI fixture');},{phase,version});
    await setUpdate('available',null);assert.equal(await page.locator('.home-controls [data-view=settings]').evaluate(n=>n.classList.contains('update-available')),false);
    await setUpdate('available','99.0.0');await page.waitForFunction(()=>document.querySelector('.home-controls [data-view=settings]').classList.contains('update-available'));
    await setUpdate('error','99.0.0');await page.waitForFunction(()=>!document.querySelector('.home-controls [data-view=settings]').classList.contains('update-available'));
    assert.deepEqual(errors,[]);console.log('PASS: semantic-save recovery preserves the unreadable input and good backup/draft, writes remain blocked until recovery, safe mode avoids crowd/audio and portrait export, reduced motion freezes poses, and update badges follow compatible available/ready UI state only. Signature verification remains covered by updates.test.cjs.');
  }finally{if(app)await app.close();await fs.rm(directory,{recursive:true,force:true,maxRetries:10,retryDelay:100});}
})().catch(e=>{console.error(e);process.exitCode=1;});
