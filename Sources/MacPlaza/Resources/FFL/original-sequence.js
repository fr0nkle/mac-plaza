/* Original clip sequencing. Time is local to an activity; source keys stay intact. */
'use strict';
const PlazaOriginalSequence=(()=>{
  function sample(clips,activity,time,duration,index=0){
    time=Math.max(0,time);
    const seconds=name=>(clips.get(name)?.frames||0)/30;
    function clip(name,t,loop=false){const c=clips.get(name);if(!c)throw new Error('Missing original clip '+name);return {name,frame:loop?((t*30)%c.frames+c.frames)%c.frames:Math.min(c.frames,Math.max(0,t*30))};}
    function sequence(enter,loop,exit){
      const start=seconds(enter),end=seconds(exit),finish=Math.max(start,duration-end);
      if(time<start)return clip(enter,time);
      if(time<finish)return clip(loop,time-start,true);
      return clip(exit,time-finish);
    }
    switch(activity){
      case 1:return sequence('Handwaving00_o','Handwaving00_l','Handwaving00_oe');
      case 2:return clip(index%2?'Talk01_l':'Talk00_l',time,true);
      case 3:return clip('Wait00_l',time,true);
      case 4:return clip('LookAround00_o',time);
      case 5:return clip('Scratch00_o',time);
      case 6:return clip('Yawn00_o',time);
      case 7:return sequence('SquatDown00_o','SquatDown00_l','SquatDown00_oe');
      case 8:return clip('MessageHappy00_l',time,true);
      case 9:{const start=seconds('MessageSurprise00_o');return time<start?clip('MessageSurprise00_o',time):clip('MessageSurprise00_l',time-start,true);}
      case 10:return clip('Bow00_o',time);
      default:return clip('Wait00_l',time+index*.23,true);
    }
  }
  return {sample};
})();
if(typeof module!=='undefined')module.exports=PlazaOriginalSequence;
