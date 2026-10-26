'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const main=fs.readFileSync(path.join(__dirname,'../src/main.cjs'),'utf8');
const action=main.slice(main.indexOf('appIconImage:async'),main.indexOf('\n  locateApp:',main.indexOf('appIconImage:async'))).trim().replace(/,$/,'');
test('Windows home icon uses resolved executable while launch keeps the original shortcut',async()=>{
  const entry={id:'test',path:'C:\\Start Menu\\Character Map.lnk',executable:'C:\\Windows\\System32\\charmap.exe'};
  const requested=[];const context=vm.createContext({homeCatalog:()=>[entry],app:{getFileIcon:async file=>{requested.push(file);return{toDataURL:()=> 'data:image/png;base64,icon'};}}});
  const actions=vm.runInContext('({'+action+'})',context);
  assert.equal(await actions.appIconImage('test'),'data:image/png;base64,icon');
  assert.deepEqual(requested,[entry.executable]);
  assert.equal(entry.path,'C:\\Start Menu\\Character Map.lnk');
  await actions.appIconImage('test');assert.equal(requested.length,1,'reuse cached icon');
});
