'use strict';
const {_electron:electron}=require('playwright');
const assert=require('node:assert/strict'),fs=require('node:fs/promises'),path=require('node:path'),os=require('node:os');
const root=path.resolve(__dirname,'..'),core=require('../src/core.cjs');
async function main(){
  const directory=await fs.mkdtemp(path.join(os.tmpdir(),'plaza-parity-'));
  const result=path.join(root,'test-results');await fs.mkdir(result,{recursive:true});
  const document=core.document();document.settings={population:20,rotateHome:false};
  await fs.writeFile(path.join(directory,'plaza.json'),JSON.stringify({origin:core.DEFAULT_SERVICE,accounts:{offline:document},apps:Array.from({length:12},(_,i)=>({id:require('node:crypto').randomUUID(),label:'App '+(i+1),bundleID:'test.app.'+i,path:'',icon:''}))}));
  let app,page;const errors=[];
  try{
    app=await electron.launch({...(process.env.PLAZA_EXECUTABLE?{executablePath:process.env.PLAZA_EXECUTABLE}:{}),args:[...(process.env.PLAZA_EXECUTABLE?[]:[root]),'--user-data-dir='+directory],timeout:60000});page=await app.firstWindow();page.on('pageerror',e=>errors.push(e.message));
    await page.waitForFunction(()=>document.body.dataset.sceneReady==='true',null,{timeout:60000});
    await page.evaluate(()=>plaza.call('engine',{command:'finishEntrance',args:{}}));
    await page.waitForFunction(()=>plazaScene.surface().iframe.contentWindow.plazaFFL.diagnostics().roster.every(r=>r.visible));
    const diagnostics=await page.evaluate(()=>plazaScene.surface().call('diagnostics'));assert.equal(diagnostics.rigs,20);assert(diagnostics.drawCalls>0);console.log('Crowd diagnostics:',JSON.stringify({rigs:diagnostics.rigs,drawCalls:diagnostics.drawCalls,positions:diagnostics.roster.slice(0,2)}));
    const png=await page.evaluate(()=>plazaScene.surface().call('snapshot'));await fs.writeFile(path.join(result,'crowd-render.png'),Buffer.from(png.split(',')[1],'base64'));await page.screenshot({path:path.join(result,'parity-plaza.png')});
    await page.locator('#zoom-in').click();assert.equal(await page.locator('#zoom-reset').textContent(),'110%');await page.locator('#zoom-reset').click();
    await page.locator('.home-controls [data-view=maker]').click();await page.waitForFunction(()=>document.querySelectorAll('#feature-grid img').length===12,null,{timeout:60000});await page.screenshot({path:path.join(result,'mii-maker.png')});
    await page.getByRole('button',{name:'Eyes category',exact:true}).click();await page.waitForFunction(()=>document.querySelectorAll('#feature-grid img').length===12);await page.getByRole('button',{name:'Eyes style 5',exact:true}).click();await page.fill('#mii-name','Win Mii');await page.getByRole('button',{name:'Save Mii',exact:true}).click();await page.waitForFunction(()=>document.querySelector('#greeting').textContent.includes('Win Mii'));
    const character=await page.evaluate(async()=>{const s=await plaza.call('state'),encoded=await plaza.call('engine',{command:'encodeMii',args:{avatar:s.document.avatar}});return await plaza.call('engine',{command:'decodeMii',args:encoded});});assert.equal(character.name,'Win Mii');assert.equal(character.eyes,4);
    await page.locator('#music').click();await page.waitForFunction(()=>PlazaMusic.diagnostics().voices.some(v=>v.playing));await page.locator('.home-controls [data-view=friends]').click();await page.waitForFunction(()=>PlazaMusic.diagnostics().role==='friends');await page.locator('#close-panel').click();await page.waitForFunction(()=>PlazaMusic.diagnostics().role==='plaza');await page.locator('#music').click();
    if(process.platform==='win32'){
      await page.locator('#use-wallpaper').click();await page.waitForFunction(()=>document.body.classList.contains('wallpaper'));
      const nativeState=await app.evaluate(({app})=>{const native=require(app.isPackaged?require('node:path').join(process.resourcesPath,'native/plaza_native.node'):require('node:path').join(app.getAppPath(),'native/runtime/plaza_native.node'));const main=require('electron').BrowserWindow.getAllWindows()[0];const assertNative=JSON.parse(native.wallpaperStatus(main.getNativeWindowHandle()));return{desktop:assertNative,discord:JSON.parse(native.discordSnapshot()),environment:JSON.parse(native.environment())};});
      assert.equal(nativeState.desktop.attached,true);assert.equal(nativeState.discord.state,'disconnected');assert.deepEqual(nativeState.discord.friends,[]);assert.equal(typeof nativeState.environment.otherAudio,'boolean');
      await page.keyboard.press('Escape');assert.equal((await page.evaluate(()=>plaza.call('state'))).wallpaper.interactive,false);
      await page.evaluate(()=>plaza.call('wallpaper',{action:'interactive',value:true}));
      const opened=app.waitForEvent('window');await page.evaluate(()=>plaza.call('panel','friends'));const companion=await opened;await companion.waitForSelector('#friend-search');await companion.close();
      await page.evaluate(()=>plaza.call('wallpaper',{action:'restore'}));await page.waitForFunction(()=>!document.body.classList.contains('wallpaper'));assert.equal((await page.evaluate(()=>plaza.call('state'))).wallpaper.active,false);
    }
    assert.deepEqual(errors,[]);console.log('Parity passed: shared crowd, app slots, zoom, Mii Maker, native Mii codec, music roles'+(process.platform==='win32'?', wallpaper attachment, passive input, companion windows, restoration and SDK runtime loading.':'.'));
  }catch(error){if(page){console.error('UI status:',await page.locator('#status').textContent());await page.screenshot({path:path.join(result,'parity-failure.png')});}throw error;}finally{if(app)await app.close();await fs.rm(directory,{recursive:true,force:true});}
}
main().catch(error=>{console.error(error);process.exitCode=1;});
