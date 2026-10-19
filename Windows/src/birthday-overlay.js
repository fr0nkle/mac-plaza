'use strict';
const parameters=new URLSearchParams(location.search),still=parameters.get('reduced')==='1'||matchMedia('(prefers-reduced-motion: reduce)').matches;
document.querySelector('h1').textContent='Happy birthday, '+(parameters.get('name')||'You')+'!';document.body.classList.toggle('still',still);
if(!still){const canvas=document.querySelector('canvas'),context=canvas.getContext('2d'),started=performance.now(),colors=['#ffdf47','#f99b33','#ffdf47','#9de5bd','#ffdf47','#fff'];
  const draw=time=>{const width=innerWidth,height=innerHeight,ratio=Math.min(devicePixelRatio,2);if(canvas.width!==width*ratio||canvas.height!==height*ratio){canvas.width=width*ratio;canvas.height=height*ratio;}context.setTransform(ratio,0,0,ratio,0,0);context.clearRect(0,0,width,height);const elapsed=(time-started)/1000;
    for(let i=0;i<96;i++){const age=Math.max(0,elapsed-i%12*.065),life=Math.min(1,age/4.7),x=width*((i*37)%101)/100+Math.sin(i*2.7+age)*28,y=-18+height*age/5.4+i%7*25,r=2.5+i%4;context.globalAlpha=Math.min(1,age*2)*Math.max(0,1-life)*.85;context.fillStyle=colors[i%6];context.beginPath();if(i%3===0){for(const [dx,dy]of [[0,-1.7],[.4,-.4],[1.7,0],[.4,.4],[0,1.7],[-.4,.4],[-1.7,0],[-.4,-.4]])context.lineTo(x+dx*r,y+dy*r);context.closePath();}else context.ellipse(x,y,r/2,r*.75,0,0,Math.PI*2);context.fill();}if(elapsed<6)requestAnimationFrame(draw);};requestAnimationFrame(draw);
}
