const {test}=require('node:test'),assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const core=require('../src/core.cjs'),portable=require('../src/portable.cjs');
test('portable Mac documents omit local app paths and convert Foundation dates in both directions',()=>{
  const doc=core.document();doc.avatars=[doc.avatar];doc.settings={population:160,rotateHome:true};doc.privateNotes=[{id:randomUUID(),author:doc.avatar,text:'Private',drawing:[],drawingDescription:'',created:1700000000}];doc.remoteNotes=[{text:'Remote friend note'}];
  const value=portable.exportDocument(doc,[{id:randomUUID(),label:'Steam',bundleID:'com.valvesoftware.steam',path:'C:/private/Steam.exe',bookmark:'private'}]);
  assert.equal(value.apps[0].path,undefined);assert.equal(value.apps[0].bookmark,undefined);assert.equal(value.notes.length,1);assert.equal(value.notes[0].shared,false);assert.equal(value.notes[0].created,1700000000-978307200);
  const restored=portable.importDocument(value,doc);assert.equal(restored.privateNotes[0].created,1700000000);assert.deepEqual(restored.remoteNotes,doc.remoteNotes);assert.equal(restored.settings.rotateHome,true);
});
