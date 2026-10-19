'use strict';
const fs=require('node:fs'),path=require('node:path');
// Same role/file mapping as Mac PlazaAudio.Track and PlazaUISounds.Cue.
const tracks={plaza:['warawara-home.m4a','WaraWara Plaza'],maker:['mii-maker.m4a','Mii Maker'],friends:['friends-menu.m4a','Friends Menu'],settings:['system-settings.m4a','System Settings'],writing:['note-writing.m4a','Writing Notes'],miiverse:['miiverse.m4a','Miiverse'],miiverseAlternate:['miiverse-alternate.m4a','Alternate Miiverse Theme'],uiClick:['UI/click.wav','Click'],uiBack:['UI/back.wav','Back']};
function readable(file){try{return fs.statSync(file).isFile();}catch{return false;}}
function load(directory,imported={},exists=readable){
  const result={};for(const [role,[name,label]]of Object.entries(tracks)){const file=path.join(directory,name);if(exists(file))result[role]={file,name:label};if(imported[role]&&exists(imported[role].file))result[role]=imported[role];}return result;
}
module.exports={tracks,load};
