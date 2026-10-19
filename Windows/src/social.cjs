'use strict';
const {randomUUID}=require('node:crypto');
const {avatar,validateAvatar}=require('./core.cjs');
function validateFriends(value){
  if(!value||!['ready','connecting','disconnected','authorization-required','account-mismatch'].includes(value.state)||!Array.isArray(value.friends)||value.friends.length>1000)throw new Error('Discord returned an invalid friend snapshot.');
  const ids=new Set();for(const friend of value.friends){if(typeof friend.discordID!=='string'||!/^\d{1,20}$/.test(friend.discordID)||BigInt(friend.discordID)===0n||BigInt(friend.discordID)>=2n**64n||ids.has(friend.discordID)||typeof friend.displayName!=='string'||!friend.displayName.trim()||[...friend.displayName].length>80||!['online','idle','dnd','offline','unknown'].includes(friend.presence))throw new Error('Discord returned an invalid friend.');ids.add(friend.discordID);}
  if(value.state!=='ready'&&value.friends.length)throw new Error('Discord friends are not ready.');return value;
}
class FriendRoster{
  constructor(){this.temporary=new Map();}
  reset(){this.temporary.clear();}
  resolve(records,snapshot,document,games={games:[],customStatuses:[]},threads=[]){
    const linked=new Map(snapshot.friends.map(f=>[f.discordID,f]));for(const note of threads){if(note.discordID&&!linked.has(note.discordID))linked.set(note.discordID,{id:note.ownerID,discordID:note.discordID,displayName:note.displayName,avatar:note.author,note:''});}const hidden=new Set(document.hiddenFriends||[]);const now=Date.now()/1000;
    const roster=[];for(const record of records){if(hidden.has(record.discordID))continue;let shared=linked.get(record.discordID);
      if(shared){validateAvatar(shared.avatar);shared={...shared,presence:record.presence};}
      else{
        if(!this.temporary.has(record.discordID)){const a=avatar(record.displayName.slice(0,24));a.skin=Math.floor(Math.random()*6);a.hair=Math.floor(Math.random()*132);a.hairColor=Math.floor(Math.random()*8);a.outfit=Math.floor(Math.random()*12);a.height=.3+Math.random()*.5;a.build=.25+Math.random()*.5;this.temporary.set(record.discordID,{id:randomUUID(),avatar:a});}
        const fallback=this.temporary.get(record.discordID),assignment=document.friendAssignments?.[record.discordID],a=structuredClone(assignment||fallback.avatar);a.id=fallback.avatar.id;a.name=[...record.displayName].slice(0,24).join('');
        shared={...record,id:fallback.id,avatar:a,note:'',temporaryAvatar:true,locallyAssignedAvatar:!!assignment};
      }
      const visible=!['offline','unknown'].includes(record.presence);
      const activity=games.games?.find(g=>g.discordID===record.discordID&&now-g.observedAt>=-60&&now-g.observedAt<90);
      if(activity&&visible)shared.activities=[{name:activity.name,source:'discord',active:activity.active!==false,observedAt:activity.observedAt}];
      const custom=games.customStatuses?.find(g=>g.discordID===record.discordID&&now-g.observedAt>=-60&&now-g.observedAt<90);if(custom&&visible)shared.customStatus=custom;
      roster.push({...shared,displayName:record.displayName,discordID:record.discordID,presence:record.presence});
    }
    return roster.filter(f=>f.locallyAssignedAvatar).concat(roster.filter(f=>!f.locallyAssignedAvatar));
  }
}
function recipients(records,hidden=[]){const excluded=new Set(hidden);return records.filter(f=>!excluded.has(f.discordID)).map(f=>f.discordID);}
module.exports={validateFriends,FriendRoster,recipients};
