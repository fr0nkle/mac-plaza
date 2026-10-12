#!/usr/bin/env node
// Numeric tests for the shipping solver, no graphics or Nintendo resource needed.
const assert=require('node:assert/strict');
const M=require('../Sources/MacPlaza/Resources/FFL/motion.js');
let contacts=0;
for(const amount of [0,.15,.5,1])for(let frame=0;frame<720;frame++){
  const phase=frame/720*2*Math.PI,p=M.solve(1,phase,amount,frame/30);
  for(let side=0;side<2;side++){
    const [h,k,a]=p.legs[side],f=p.feet[side];
    const z=-.34*Math.sin(h)-.36*Math.sin(h+k);
    const y=.764+p.bob-.34*Math.cos(h)-.36*Math.cos(h+k);
    assert.ok(Math.abs(z-f.z)<1e-9,'IK foot must reach its forward target');
    assert.ok(Math.abs(y-(.065+f.y))<1e-9,'Sole must reach its height target');
    assert.ok(y>=.065-1e-9,'No sole may penetrate the floor');
    assert.ok(Math.abs(h+k+a-f.pitch)<1e-9,'Ankle must counter-rotate the leg');
    if(f.planted)contacts++;
  }
}
// At full pace, translation and stance travel cancel exactly, including stature.
for(const stature of [.72,.92,1.12]){
  let start;
  for(let frame=0;frame<60;frame++){
    const u=frame/100,f=M.foot(u*2*Math.PI,1),world=(u*.48+f.z)*stature;
    if(start===undefined)start=world;
    assert.ok(Math.abs(world-start)<1e-10,'Planted foot must not slide');
  }
}
// No jump at the stance/swing boundary or full-cycle wrap.
for(const boundary of [0,.6,1]){
  const l=M.foot((boundary-1e-7)*2*Math.PI,1),r=M.foot((boundary+1e-7)*2*Math.PI,1);
  assert.ok(Math.abs(l.z-r.z)<1e-6 && Math.abs(l.y-r.y)<1e-6);
}
for(let state=0;state<=5;state++)for(const social of [true,false])for(let t=0;t<5;t+=.03){
  const p=M.solve(state,t*4,.7,t,social,.2,3.5);
  assert.ok(JSON.stringify(p).indexOf('null')===-1,'Every pose must be finite');
  assert.ok(p.hop>=0 && p.hop<.09,'Reactions stay bounded');
}
const listener=M.solve(5,0,0,1,true),speaker=M.solve(3,0,0,1,true),wave=M.solve(3,0,0,1,false);
assert.ok(Math.abs(listener.ra[2])<.2 && speaker.ra[2]<.5 && wave.ra[2]>1.5,'Listening, speaking and greeting must remain distinct');
console.log(`Motion checks passed: ${contacts} planted contacts, four paces, three statures, six states.`);
