'use strict';
const {_electron:electron}=require('playwright'),assert=require('node:assert/strict'),fs=require('node:fs/promises'),path=require('node:path'),os=require('node:os');
const core=require('../src/core.cjs'),{miiverse}=require('./windows.cjs');
async function main(){
  const directory=await fs.mkdtemp(path.join(os.tmpdir(),'plaza-window-')),root=path.resolve(__dirname,'..');let app;
  try{
    const document=core.document();document.settings={population:20,ambientSound:true};document.draft.text='Keep this draft';
    await fs.writeFile(path.join(directory,'plaza.json'),JSON.stringify({audienceVersion:1,origin:core.DEFAULT_SERVICE,accounts:{offline:document}}));
    const launch=async()=>{app=await electron.launch({...(process.env.PLAZA_EXECUTABLE?{executablePath:process.env.PLAZA_EXECUTABLE}:{}),args:[...(process.env.PLAZA_EXECUTABLE?[]:[root]),'--user-data-dir='+directory],timeout:60000});return app.firstWindow();};
    let plaza=await launch();await plaza.waitForFunction(()=>document.body.dataset.sceneReady==='true');
    const errors=[];plaza.on('pageerror',e=>errors.push(e.message));
    await plaza.click('#miiverse-button');let panel=await miiverse(app);panel.on('pageerror',e=>errors.push(e.message));
    const windowInfo=await app.evaluate(({BrowserWindow})=>{const w=BrowserWindow.getAllWindows().find(w=>w.getTitle()==='Miiverse');return{count:BrowserWindow.getAllWindows().length,resizable:w.isResizable(),min:w.getMinimumSize(),bounds:w.getBounds()};});
    assert.equal(windowInfo.count,2);assert.equal(windowInfo.resizable,true);assert(windowInfo.min[0]>=720&&windowInfo.min[1]>=540);assert.equal(await panel.evaluate(()=>typeof require),'undefined');
    await plaza.waitForFunction(()=>PlazaMusic.diagnostics().role==='miiverse');
    const positions=await plaza.evaluate(async()=>JSON.stringify((await plazaScene.surface().call('diagnostics')).roster));
    await plaza.waitForFunction(async previous=>JSON.stringify((await plazaScene.surface().call('diagnostics')).roster)!==previous,positions);
    await app.evaluate(({BrowserWindow})=>BrowserWindow.getAllWindows().find(w=>w.getTitle()==='Miiverse').setSize(800,600));
    await panel.waitForFunction(()=>innerWidth<=800);assert.equal(await panel.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true);
    await panel.getByRole('button',{name:'My Notes · 0',exact:true}).click();
    await app.evaluate(({BrowserWindow})=>BrowserWindow.getAllWindows().find(w=>w.getTitle()==='Miiverse').minimize());
    await plaza.waitForFunction(()=>PlazaMusic.diagnostics().role==='plaza');
    await app.evaluate(({BrowserWindow})=>BrowserWindow.getAllWindows().find(w=>w.getTitle()==='Miiverse').restore());
    await plaza.waitForFunction(()=>PlazaMusic.diagnostics().role==='miiverse');
    assert.deepEqual(await app.evaluate(({BrowserWindow})=>BrowserWindow.getAllWindows().find(w=>w.getTitle()==='Miiverse').getSize()),[800,600]);
    await panel.click('#close-panel');await plaza.waitForFunction(()=>PlazaMusic.diagnostics().role==='plaza');
    assert.equal((await plaza.evaluate(()=>plaza.call('state'))).document.draft.text,'Keep this draft');
    await plaza.click('#miiverse-button');panel=await miiverse(app);
    assert.equal(await panel.locator('#communities .selected').textContent(),'All Notes · 0');
    await fs.mkdir(path.join(root,'test-results'),{recursive:true});await panel.screenshot({path:path.join(root,'test-results/miiverse-window-800.png')});
    await app.close();app=null;
    plaza=await launch();await plaza.click('#miiverse-button');panel=await miiverse(app);
    const size=await app.evaluate(({BrowserWindow})=>BrowserWindow.getAllWindows().find(w=>w.getTitle()==='Miiverse').getSize());assert.deepEqual(size,[800,600]);
    assert.deepEqual(errors,[]);
    console.log('PASS: separate resizable Miiverse, minimum size, moving background plaza, music roles on minimize/restore/close, all-post reset, preserved draft and saved bounds across restart.');
  }finally{if(app)await app.close();await fs.rm(directory,{recursive:true,force:true,maxRetries:10,retryDelay:100});}
}
main().catch(error=>{console.error(error);process.exitCode=1;});
