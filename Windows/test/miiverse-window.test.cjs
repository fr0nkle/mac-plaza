const {test}=require('node:test'),assert=require('node:assert/strict');
const {fitBounds}=require('../src/miiverse-window.cjs');
test('Miiverse restores usable bounds after monitor removal and on small displays',()=>{
  assert.deepEqual(fitBounds({x:5000,y:-400,width:1000,height:720},{x:0,y:0,width:1920,height:1080}),{x:920,y:0,width:1000,height:720});
  assert.deepEqual(fitBounds(null,{x:-1280,y:0,width:1280,height:800}),{x:-1140,y:40,width:1000,height:720});
  assert.deepEqual(fitBounds({width:NaN,height:-1},{x:0,y:0,width:640,height:480}),{x:0,y:0,width:640,height:480});
});
