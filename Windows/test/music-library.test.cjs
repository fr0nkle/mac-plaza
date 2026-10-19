'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict'),path=require('node:path'),library=require('../src/music-library.cjs');
test('Mac soundtrack/effect roles use the same local files, imports override defaults, and missing selections fall back',()=>{
  const available=new Set(Object.values(library.tracks).map(([name])=>path.join('Audio',name))),exists=file=>available.has(file),defaults=library.load('Audio',{},exists);assert.equal(Object.keys(defaults).length,9);assert.equal(defaults.miiverseAlternate.file,path.join('Audio','miiverse-alternate.m4a'));assert.equal(defaults.uiBack.file,path.join('Audio','UI/back.wav'));
  const imported={file:'local.wav',name:'My theme'};assert.deepEqual(library.load('Audio',{miiverse:imported},exists).miiverse,defaults.miiverse);available.add('local.wav');assert.equal(library.load('Audio',{miiverse:imported},exists).miiverse,imported);assert.deepEqual(library.load('Audio',{},()=>false),{});
});
