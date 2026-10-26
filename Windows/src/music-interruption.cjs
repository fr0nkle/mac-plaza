'use strict';
// Require a player-declared Music session AND audible output from that player.
// A capture session, notification, unknown media type or missing probe is not music.
const identity=value=>String(value||'').toLowerCase().replace(/\.exe$/,'');
function own(value){return /^(plaza|windows plaza|plaza-windows|org\.squidproductions\.plaza\.windows)(!.*)?$/.test(identity(value));}
function hasOtherMusic(sample){
  if(sample?.available!==true||!Array.isArray(sample.media)||!Array.isArray(sample.audio))return false;
  return sample.media.some(m=>m.status==='Playing'&&m.type==='Music'&&!own(m.appId)&&sample.audio.some(a=>
    a.active===true&&a.muted===false&&Number.isFinite(a.peak)&&a.peak>0.0005&&!own(a.process)&&!own(a.appId)&&
    [a.appId,a.process].some(id=>identity(id)&&identity(id)===identity(m.appId))));
}
function createGate({onsetMs=1500}={}){
  let since=null;
  return(sample,now)=>{if(!hasOtherMusic(sample)){since=null;return false;}if(since===null)since=now;return now-since>=onsetMs;};
}
// Keep OS lock/suspend handling, but visual coverage/idle desktop is not music.
function muteMusic({locked=false,suspended=false,otherMusic=false}={}){return !!(locked||suspended||otherMusic);}
module.exports={hasOtherMusic,createGate,muteMusic};
