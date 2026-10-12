/* Original local animation rig. +Z is forward; rotations are radians.
 * A 0.48-unit gait cycle has a 60% planted stance. Leg IK keeps the sole on
 * the floor through stance; swing lifts the toe, not the entire character.
 * This file has no DOM/WebGL dependency, so contacts can be tested numerically.
 */
'use strict';
const PlazaMotion=(()=>{
  const tau=2*Math.PI,clamp=(v,a,b)=>Math.max(a,Math.min(b,v)),smooth=t=>t*t*(3-2*t);
  function foot(phase,amount){
    const u=((phase/tau)%1+1)%1,stance=.60;
    if(u<stance)return {z:(.144-.288*u/stance)*amount,y:0,pitch:0,planted:true};
    const t=(u-stance)/(1-stance);
    return {z:(-.144+.288*smooth(t))*amount,y:.075*Math.pow(Math.sin(Math.PI*t),1.5)*amount,pitch:-.25*Math.sin(Math.PI*t)*amount,planted:false};
  }
  function leg(f,hipY){
    const upper=.34,lower=.36,y=hipY-.065-f.y,d=clamp(Math.hypot(y,f.z),.05,upper+lower-.00001);
    const knee=Math.PI-Math.acos(clamp((upper*upper+lower*lower-d*d)/(2*upper*lower),-1,1));
    const hip=Math.atan2(-f.z,y)-Math.acos(clamp((upper*upper+d*d-lower*lower)/(2*upper*d),-1,1));
    return [hip,knee,f.pitch-hip-knee];
  }
  function solve(state,phase,amount,time=0,social=false,lookYaw=0,turn=0){
    amount=clamp(amount,0,1);
    const stride=Math.sin(phase),a=time*3,left=foot(phase,amount),right=foot(phase+Math.PI,amount);
    let bob=-.001-.018*amount*Math.pow(Math.cos(phase),2),hop=0;
    // Lower the pelvis only as much as needed to keep both targets reachable.
    bob=Math.min(bob,...[left,right].map(f=>.065+f.y+Math.sqrt(.699*.699-f.z*f.z)-.764));
    const la=[-stride*.22*amount,0,-.08],ra=[stride*.22*amount,0,.08];
    const le=[-.045,0,0],re=[-.045,0,0],torso=[.025*amount,0,-stride*.018*amount-clamp(turn,-3.5,3.5)*.009*amount];
    const head=[-.025*amount,lookYaw+Math.sin(time*.85)*.025,-torso[2]*.5];
    let wrist=0;
    if(state===0){torso[2]=Math.sin(time*1.5)*.006;head[0]=Math.sin(time*1.1)*.015;}
    if(state===2){torso[1]=clamp(turn*.025,-.09,.09);head[1]+=clamp(turn*.045,-.16,.16);}
    if(state===3){
      if(social){ra[0]=-.42-.12*Math.sin(a);ra[2]=.18;re[0]=-.85-.25*Math.sin(a*.7);head[0]=Math.sin(a*.6)*.035;}
      else{ra[2]=2.0+Math.sin(a*2.8)*.12;ra[0]=-.12;re[0]=-.25;wrist=Math.sin(a*4.8)*.32;head[2]=-.045;}
    }
    if(state===4){
      const beat=(time%1.05+1.05)%1.05,flight=clamp((beat-.18)/.52,0,1);
      hop=time<0?0:.085*Math.sin(Math.PI*flight);bob-=.022*Math.sin(Math.PI*clamp(beat/.18,0,1));
      la[2]=-2.35;ra[2]=2.35;le[0]=re[0]=-.16;head[0]=-.07;
    }
    if(state===5){
      if(social){head[0]=.055+.07*Math.sin(a*.75);la[0]=-.06;ra[0]=-.08;}
      else{la[0]=ra[0]=-.24;le[0]=re[0]=-.5;la[2]=-.22;ra[2]=.22;head[0]=-.05;}
    }
    const legs=[leg(left,.764+bob),leg(right,.764+bob)];
    return {bob,hop,la,ra,le,re,torso,head,wrist,legs,feet:[left,right]};
  }
  return {solve,foot,leg};
})();
if(typeof module!=='undefined')module.exports=PlazaMotion;
