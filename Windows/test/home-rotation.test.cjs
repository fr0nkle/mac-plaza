'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');

// Exercise the shipping renderer's async bridge consumer without opening a GUI.
// Foundation UUID Codable emits uppercase strings; discovered Windows IDs are lowercase.
const renderer=fs.readFileSync(path.join(__dirname,'../src/renderer.js'),'utf8');
const rotation=renderer.slice(renderer.indexOf('async function rotateHome(){'),renderer.indexOf('\nfunction renderApps(){'));
test('Swift UUID casing preserves discovered apps, paths and icons in visible home order',async()=>{
  const apps=Array.from({length:12},(_,i)=>({id:`a87613ba-857e-4bad-86d3-f35b867416${String(i).padStart(2,'0')}`,label:`App ${i}`,bundleID:`windows.app.${i}`,path:`C:\\Synthetic Apps\\App ${i}.lnk`,icon:i?'':'data:image/png;base64,fixture'}));
  let rendered=[];
  const context=vm.createContext({state:{document:{settings:{}},apps:[],homeCatalog:apps,history:[]},companion:null,rotating:false,editingApps:false,snapshot:null,rotationSignature:'',homeOrder:null,PlazaCatalog:{friendGames:()=>[]},call:async(action,value)=>{assert.equal(action,'engine');assert.equal(value.command,'rotateHome');return value.args.fallback.slice().reverse().map(a=>({...a,id:a.id.toUpperCase()}));},renderApps:()=>{rendered=Array.from(context.homeOrder);}});
  vm.runInContext(rotation,context);
  await context.rotateHome();
  assert.equal(rendered.length,12,'every selected app must reach tile rendering');
  assert.deepEqual(rendered,apps.slice().reverse(),'retain original catalog objects, including Windows launch paths and icons');
});
