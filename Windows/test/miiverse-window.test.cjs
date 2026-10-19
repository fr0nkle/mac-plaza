const {test}=require('node:test'),assert=require('node:assert/strict');
const {fitBounds}=require('../src/miiverse-window.cjs');
test('Miiverse restores usable bounds after monitor removal and on small displays',()=>{
  assert.deepEqual(fitBounds({x:5000,y:-400,width:1000,height:720},{x:0,y:0,width:1920,height:1080}),{x:920,y:0,width:1000,height:720});
  assert.deepEqual(fitBounds(null,{x:-1280,y:0,width:1280,height:800}),{x:-1140,y:40,width:1000,height:720});
  assert.deepEqual(fitBounds({width:NaN,height:-1},{x:0,y:0,width:640,height:480}),{x:0,y:0,width:640,height:480});
});
test('Miiverse retains a connected saved display, falls back after removal and includes native chrome in minimum bounds',()=>{const {displayArea}=require('../src/miiverse-window.cjs'),left={x:-1280,y:0,width:1280,height:800},main={x:0,y:0,width:1920,height:1080};assert.equal(displayArea({x:-1200,y:100,width:800,height:600},[main,left],main),left);assert.equal(displayArea({x:-2400,y:0,width:800,height:600},[main],main),main);assert.equal(fitBounds({width:720,height:540},main,{minWidth:736,minHeight:594}).height,594);});
