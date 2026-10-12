const assert=require('node:assert/strict'),fs=require('node:fs');
const {sample}=require('../Sources/MacPlaza/Resources/FFL/original-sequence.js');
const frames={'Handwaving00_o':20,'Handwaving00_l':15,'Handwaving00_oe':25,'SquatDown00_o':50,'SquatDown00_l':120,'SquatDown00_oe':50,'Wait00_l':135,'Talk00_l':130,'Talk01_l':130,'LookAround00_o':144,'Scratch00_o':90,'Yawn00_o':160,'Bow00_o':60,'MessageHappy00_l':50,'MessageSurprise00_o':45,'MessageSurprise00_l':100};
const clips=new Map(Object.entries(frames).map(([name,frames])=>[name,{name,frames}]));
if(process.env.PLAZA_MENU_QA_RESOURCE){const read=require('../Sources/MacPlaza/Resources/FFL/menu-assets.js').read;const pack=read(fs.readFileSync(process.env.PLAZA_MENU_QA_RESOURCE));for(const a of pack.animations)clips.set(a.name,a);}
for(const [activity,enter,loop,exit,duration] of [[1,'Handwaving00_o','Handwaving00_l','Handwaving00_oe',2.5],[7,'SquatDown00_o','SquatDown00_l','SquatDown00_oe',340/30]]){
 assert.deepEqual(sample(clips,activity,0,duration),{name:enter,frame:0});
 const a=clips.get(enter).frames/30,b=duration-clips.get(exit).frames/30;
 assert.equal(sample(clips,activity,a+.01,duration).name,loop);
 assert.equal(sample(clips,activity,b+.01,duration).name,exit);
 assert(Math.abs(sample(clips,activity,duration,duration).frame-clips.get(exit).frames)<1e-8);
 for(let t=0;t<duration;t+=.013){const r=sample(clips,activity,t,duration);assert(r.frame>=0&&r.frame<=clips.get(r.name).frames);}
}
for(let activity=0;activity<=10;activity++){const r=sample(clips,activity,0,12);if(activity!==0)assert.equal(r.frame,0);assert(clips.has(r.name));}
assert.equal(sample(clips,2,130/30,130/30).frame,0);
console.log('Original activity sequencing passed: source frames, greeting/sit entrance-loop-exit, and all activity starts.');
