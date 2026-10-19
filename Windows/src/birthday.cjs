'use strict';
const fs=require('node:fs/promises'),path=require('node:path');
function days(month){return month===2?29:[4,6,9,11].includes(month)?30:Number.isInteger(month)&&month>=1&&month<=12?31:0;}
function valid(month,day){return Number.isInteger(month)&&Number.isInteger(day)&&((month===0&&day===0)||(day>=1&&day<=days(month)));}
function eligible(state){return !!state.loaded&&!state.demo&&!state.recoveryRequired&&!state.safeMode&&!state.locked&&!state.suspended&&state.visible&&!state.sheet&&!state.preview&&!state.covered&&!state.celebrating;}
class BirthdayReceipt{
  constructor(file){this.file=file;this.year=null;this.loaded=false;}
  async load(){if(this.loaded)return;try{const year=JSON.parse(await fs.readFile(this.file,'utf8'));if(Number.isInteger(year))this.year=year;}catch{}this.loaded=true;}
  async claim(primary,now=new Date()){
    await this.load();const {birthMonth:month,birthDay:day}=primary.features||{},year=now.getFullYear();
    if(!valid(month,day)||!month||this.year===year||month!==now.getMonth()+1||day!==now.getDate())return false;
    await fs.mkdir(path.dirname(this.file),{recursive:true});
    await fs.writeFile(this.file+'.tmp',JSON.stringify(year),{mode:0o600});await fs.rename(this.file+'.tmp',this.file);this.year=year;return true;
  }
}
class BirthdayOverlay{
  constructor(BrowserWindow){this.BrowserWindow=BrowserWindow;this.window=null;this.timer=null;}
  async show(primary,display,reducedMotion){
    if(this.window)return;
    const w=new this.BrowserWindow({...display.bounds,show:false,frame:false,transparent:true,hasShadow:false,focusable:false,skipTaskbar:true,alwaysOnTop:true,resizable:false,
      webPreferences:{sandbox:true,contextIsolation:true,nodeIntegration:false}});
    this.window=w;w.setIgnoreMouseEvents(true,{forward:true});w.setMenu(null);
    w.webContents.setWindowOpenHandler(()=>({action:'deny'}));w.webContents.on('will-navigate',e=>e.preventDefault());
    w.on('closed',()=>{if(this.window===w)this.window=null;clearTimeout(this.timer);});
    try{await w.loadFile(path.join(__dirname,'birthday.html'),{query:{name:primary.name,reduced:reducedMotion?'1':'0'}});if(w.isDestroyed())return;w.showInactive();this.timer=setTimeout(()=>this.dismiss(),reducedMotion?3000:6000);this.timer.unref();}
    catch(error){this.dismiss();throw error;}
  }
  dismiss(){clearTimeout(this.timer);if(this.window&&!this.window.isDestroyed())this.window.destroy();this.window=null;}
}
module.exports={days,valid,eligible,BirthdayReceipt,BirthdayOverlay};
