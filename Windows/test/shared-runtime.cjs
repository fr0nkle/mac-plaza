'use strict';
const assert=require('node:assert/strict'),{Engine}=require('../src/engine.cjs');
(async()=>{const engine=new Engine(false);try{
 const now=Date.now()/1000,friends=[{discordID:'42',displayName:'Friend',presence:'online'}],live={state:'ready',coveredDiscordIDs:['42'],games:[{discordID:'42',name:'Portal',observedAt:now,active:true}],customStatuses:[]};
 let result=await engine.call('gameHistory',{friends,snapshot:live,now});assert.equal(result.games[0].active,true);
 result=await engine.call('gameHistory',{history:result.history,friends,snapshot:{...live,games:[]},now:now+20});assert.equal(result.games[0].active,false);assert.equal(result.games[0].observedAt,now+20);
 result=await engine.call('gameHistory',{history:result.history,friends,restore:true,now:now+300});assert.equal(result.games[0].active,false);assert.equal(result.games[0].observedAt,now+20);
 result=await engine.call('gameHistory',{history:result.history,friends,snapshot:{state:'ready',coveredDiscordIDs:[],games:[]},now:now+301});assert.equal(result.games.length,0);
 await assert.rejects(engine.call('gameHistory',{friends,snapshot:{...live,coveredDiscordIDs:['99']},now}));
 let frame;for(let i=0;i<130;i++)frame=await engine.call('frame',{dt:.1,width:1000,height:700});assert.equal(frame.postPresentation,'journal');assert(frame.postCount>=1&&frame.postCount<=3);const first=frame.postCount;
 for(let i=0;i<50;i++)frame=await engine.call('frame',{dt:.1,postsHeld:true});assert.equal(frame.postPresentation,'journal');
 for(let i=0;i<240;i++)frame=await engine.call('frame',{dt:.1});assert.equal(frame.postPresentation,'friends');assert.notEqual(frame.postCount,first);
 await engine.call('configure',{population:20,reduceMotion:true});await engine.call('finishEntrance');
 const still=await engine.call('frame',{dt:.1,pauseMotion:true});
 for(let i=0;i<240;i++)frame=await engine.call('frame',{dt:.1,pauseMotion:true});
 assert.deepEqual(frame.poses,still.poses,'Pausing crowd motion preserves every pose and animation clock');assert.notEqual(frame.postPresentation,still.postPresentation,'Posts continue their independent cadence while crowd motion is paused');
 console.log('PASS: shipping Swift Discord history validation/coverage/stop/outage/restart semantics, exact Mac post cadence with held clock and changing 1–3-card density, and stationary crowd poses with independently advancing posts.');
}finally{engine.close();}})().catch(e=>{console.error(e);process.exitCode=1;});
