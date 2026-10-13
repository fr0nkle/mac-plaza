const { test } = require('node:test');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const core = require('../src/core.cjs');
const note = text => ({id:randomUUID(),author:core.avatar(),text,drawing:[],drawingDescription:'',created:123456});
test('HTTPS and local-only development origins',()=>{
  assert.equal(core.endpoint('https://plaza.example/'),'https://plaza.example');
  assert.equal(core.endpoint('http://127.0.0.1:8787'),'http://127.0.0.1:8787');
  for(const value of ['http://example.com','https://user:secret@example.com','https://example.com/path','https://example.com/?token=x','file:///tmp/plaza'])assert.throws(()=>core.endpoint(value));
});
test('only portable Mac-compatible note fields are published',()=>{
  const value=note('Hello Mac');value.author.features.creator='Private';value.author.features.birthMonth=10;value.path='C:\\private';value.bookmark='secret';value.replies=[{text:'Local reply'}];
  const wire=core.wireNote(value);assert.equal(wire.author.features.creator,'');assert.equal(wire.author.features.birthMonth,0);assert.equal(wire.path,undefined);assert.equal(wire.replies,undefined);assert.equal(value.author.features.creator,'Private');
});
test('first sign-in preserves existing account notes, edits and deletions merge by source ID',()=>{
  const own=note('Mac-authored'),other=note('A friend'),owner=randomUUID();
  const remote=[{...own,id:randomUUID(),sourceID:own.id,ownerID:owner},{...other,sourceID:other.id,ownerID:randomUUID()}];
  assert.deepEqual(core.mergeNotes(remote,owner,{}),[core.wireNote(own)]);
  const added=note('Windows-authored');const merged=core.mergeNotes(remote,owner,{[added.id]:added});assert.equal(merged.length,2);
  assert.deepEqual(core.mergeNotes(remote,owner,{[own.id]:null}),[]);
  assert.deepEqual(core.mergeNotes([],owner,{}),[]);
});
test('drawing coordinates, counts and Unicode text are bounded',()=>{
  core.validateNote(note('😀'.repeat(280)));assert.throws(()=>core.validateNote(note('😀'.repeat(281))));
  const n=note('');n.drawing=[{eraser:false,points:[{x:.3,y:.5}]}];n.drawingDescription='A dot';core.validateNote(n);
  n.drawing[0].points[0].x=NaN;assert.throws(()=>core.validateNote(n));
  n.drawing=[{eraser:false,points:[{x:1.1,y:0}]}];assert.throws(()=>core.validateNote(n));
  n.drawing=[{eraser:false,points:Array(20001).fill({x:0,y:0})}];assert.throws(()=>core.validateNote(n));
});
test('shared replacement bounds match Mac service',()=>{
  const pending={};for(let i=0;i<201;i++){const n=note('Hi');pending[n.id]=n;}assert.throws(()=>core.mergeNotes([],randomUUID(),pending));
});
