'use strict';
const { _electron: electron } = require('playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const os = require('node:os');
const { spawn } = require('node:child_process');
const root = path.resolve(__dirname,'..');
async function main(){
  const tmp=await fs.mkdtemp(path.join(os.tmpdir(),'plaza-windows-qa-'));
  const fixture=spawn(process.env.PYTHON||'python3',[path.join(__dirname,'service_fixture.py')],{stdio:['ignore','pipe','pipe']});
  let app;
  try{
    const auth=await new Promise((resolve,reject)=>{let data='';fixture.stdout.on('data',chunk=>{data+=chunk;if(data.includes('\n'))resolve(JSON.parse(data.split('\n')[0]));});fixture.on('error',reject);fixture.on('exit',code=>reject(new Error('Fixture exited '+code)));fixture.stderr.on('data',chunk=>process.stderr.write(chunk));});
    const api=async(token,method,route,body)=>{const result=await fetch(auth.origin+'/v1/'+route,{method,headers:{Authorization:'Bearer '+token,'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined});assert.equal(result.status,200);return result.json();};
    const launch=()=>electron.launch({...(process.env.PLAZA_EXECUTABLE?{executablePath:process.env.PLAZA_EXECUTABLE}:{}),args:[...(process.env.PLAZA_EXECUTABLE?[]:[root]),'--user-data-dir='+tmp],timeout:60000});
    app=await launch();assert.equal(await fs.realpath(await app.evaluate(({app})=>app.getPath('userData'))),await fs.realpath(tmp),'Tests require isolated user data');let page=await app.firstWindow();await page.waitForSelector('#write');
    // Exercise the shipping offline app, then seed only this test's encrypted
    // session through Playwright's main-process API. There is no app auth bypass.
    await page.click('#write');await page.fill('#note-text','Private Windows note');await page.selectOption('#visibility','private');await page.click('#post-note');await page.getByText('Private Windows note',{exact:true}).waitFor();
    await page.click('#write');await page.fill('#note-text','An unsent draft');await page.click('#close-composer');
    await fs.mkdir(path.join(root,'test-results'),{recursive:true});await page.screenshot({path:path.join(root,'test-results','offline.png')});
    await app.close();app=await launch();page=await app.firstWindow();await page.getByText('Private Windows note',{exact:true}).waitFor();await page.click('#write');assert.equal(await page.inputValue('#note-text'),'An unsent draft');await page.click('#close-composer');
    const encrypted=await app.evaluate(({safeStorage},value)=>safeStorage.encryptString(JSON.stringify(value)).toString('base64'),{origin:auth.origin,token:auth.windows,accountID:auth.accountID});
    await fs.writeFile(path.join(tmp,'session.bin'),Buffer.from(encrypted,'base64'));
    await app.close();app=await launch();page=await app.firstWindow();const failures=[];page.on('pageerror',error=>failures.push(error.message));
    await page.getByText('Hello Windows, from Mac!',{exact:true}).waitFor({timeout:30000});
    assert.equal(await page.getByText('Private Windows note',{exact:true}).count(),0,'Accounts must not inherit offline/private journals');
    await page.click('#write');await page.fill('#note-text','Hello Mac, from Windows!');
    const canvas=page.locator('#drawing');const box=await canvas.boundingBox();await page.mouse.move(box.x+50,box.y+70);await page.mouse.down();await page.mouse.move(box.x+150,box.y+100,{steps:8});await page.mouse.up();await page.fill('#drawing-description','A little wave');await page.fill('#topic-label','Portal 2');await page.fill('#steam-id','620');await page.click('#post-note');await page.getByText('Hello Mac, from Windows!',{exact:true}).waitFor();
    let macNotes=(await api(auth.mac,'GET','notes/threads')).notes;const windowsNote=macNotes.find(n=>n.text==='Hello Mac, from Windows!');assert(windowsNote,'Mac must receive Windows-authored note');assert(windowsNote.drawing[0].points.length>1);assert.equal(windowsNote.topic.steamAppID,620);
    assert.equal((await api(auth.stranger,'GET','notes')).notes.length,0,'Unrelated accounts must not see either friend’s notes');
    const card=page.locator('.note').filter({hasText:'Hello Windows, from Mac!'});await card.getByRole('button',{name:'♡ 0',exact:true}).click();
    await card.getByRole('textbox',{name:'Reply to Mac Mii'}).fill('Windows replies to Mac');await card.getByRole('button',{name:'Reply',exact:true}).click();await page.getByText('Windows replies to Mac',{exact:true}).waitFor();
    macNotes=(await api(auth.mac,'GET','notes/threads')).notes;const macThread=macNotes.find(n=>n.text==='Hello Windows, from Mac!');assert.equal(macThread.likeCount,1);assert.equal(macThread.replies[0].text,'Windows replies to Mac');
    await api(auth.mac,'PUT',`notes/${windowsNote.id}/like`,{liked:true});await api(auth.mac,'PUT',`notes/${windowsNote.id}/replies/${require('node:crypto').randomUUID()}`,{author:auth.macNote.author,text:'Mac replies to Windows'});await page.click('#refresh');await page.getByText('Mac replies to Windows',{exact:true}).waitFor();
    await page.screenshot({path:path.join(root,'test-results','shared-journal.png')});
    const windowsCard=page.locator('.note').filter({hasText:'Hello Mac, from Windows!'});await windowsCard.getByRole('button',{name:'Edit',exact:true}).click();await page.fill('#note-text','Edited Windows note');await page.click('#post-note');await page.getByText('Edited Windows note',{exact:true}).waitFor();macNotes=(await api(auth.mac,'GET','notes/threads')).notes;assert(macNotes.some(n=>n.text==='Edited Windows note'&&n.replies[0]?.text==='Mac replies to Windows'));
    // Switching to private retracts the note and discussion from the Mac feed.
    await page.locator('.note').filter({hasText:'Edited Windows note'}).getByRole('button',{name:'Edit',exact:true}).click();await page.selectOption('#visibility','private');await page.click('#post-note');await page.getByText('Edited Windows note',{exact:true}).waitFor();assert(!(await api(auth.mac,'GET','notes/threads')).notes.some(n=>n.sourceID===windowsNote.sourceID));
    // Revocation removes cached friend notes on the next successful poll.
    await api(auth.mac,'POST','friends/block',{id:auth.accountID});await page.click('#refresh');await page.waitForFunction(()=>!document.querySelector('#notes').textContent.includes('Hello Windows, from Mac!'));
    assert.deepEqual(failures,[]);assert.equal(await page.evaluate(()=>typeof require),'undefined');
    console.log('Desktop passed: offline persistence, draft recovery, account isolation, Mac ↔ Windows text/drawings/Steam topics, likes/replies, edit preservation, privacy retraction and block revocation.');
  }finally{if(app)await app.close();fixture.kill();await fs.rm(tmp,{recursive:true,force:true});}
}
main().catch(error=>{console.error(error);process.exitCode=1;});
