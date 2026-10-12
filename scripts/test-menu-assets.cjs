#!/usr/bin/env node
const assert=require('node:assert/strict'),fs=require('node:fs');
const M=require('../Sources/MacPlaza/Resources/FFL/menu-assets.js');
// Bounded Yaz0 literals and overlapping back-references.
const b=Buffer.alloc(21);b.write('Yaz0');b.writeUInt32BE(6,4);b[16]=0xe0;b[17]=65;b[18]=66;b[19]=67;
assert.throws(()=>M.yaz0(b));
const c=Buffer.alloc(22);c.write('Yaz0');c.writeUInt32BE(6,4);c[16]=0xe0;c[17]=65;c[18]=66;c[19]=67;c[20]=0x10;c[21]=2;
assert.equal(Buffer.from(M.yaz0(c)).toString(),'ABCABC');c[21]=9;assert.throws(()=>M.yaz0(c));
assert.throws(()=>M.read(Buffer.alloc(2048)));
// Cubic coefficients are normalized to their source key interval, then scaled.
assert.equal(M.sample({frames:[0,10],keys:[1,2,3,4,10,0,0,0],type:0,scale:2,offset:3},5),9.5);
assert.equal(M.sample({frames:[0,10],keys:[1,9,10,0],type:1,scale:1,offset:0},5),5.5);
if(process.env.PLAZA_MENU_QA_RESOURCE){
 const pack=M.read(fs.readFileSync(process.env.PLAZA_MENU_QA_RESOURCE));assert.equal(pack.animations.length,172);assert.deepEqual(pack.models.map(m=>m.positions.length/3),[940,955]);
 let endpoints=0;
 for(const clip of pack.animations)for(const bone of clip.bones)for(const curve of bone.curves){
  for(let i=0;i<curve.frames.length;i++){
   assert.equal(M.sample(curve,curve.frames[i]),curve.keys[i*(curve.type===0?4:curve.type===1?2:1)]*(curve.scale||1)+curve.offset);endpoints++;
  }
 }
 // Corrupting the outer archive must fail before any resource is installed.
 const corrupt=fs.readFileSync(process.env.PLAZA_MENU_QA_RESOURCE);corrupt.writeUInt32BE(0xffffffff,32+12);assert.throws(()=>M.read(corrupt));
 console.log(`Original menu checks passed: ${endpoints} exact source key values, 172 clips, two meshes.`);
}else console.log('Menu parser/curve checks passed; set PLAZA_MENU_QA_RESOURCE for original asset checks.');
