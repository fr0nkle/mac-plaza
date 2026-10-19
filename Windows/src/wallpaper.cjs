'use strict';
const {Tray,Menu,nativeImage,screen}=require('electron');
const path=require('node:path');
class Wallpaper {
  constructor(window,native,{save,settings,notify,panel,quit}){this.window=window;this.native=native;this.settings=settings;this.save=save;this.notify=notify;this.panel=panel;this.quit=quit;this.perform=action=>Promise.resolve().then(action).catch(error=>this.notify(error.message));this.active=false;this.interactive=true;this.quitting=false;this.restoring=false;
    if(process.platform==='win32'){
      this.tray=new Tray(nativeImage.createFromPath(path.join(__dirname,'icon.ico')));this.tray.setToolTip('Plaza');this.tray.on('double-click',()=>this.perform(()=>this.active?this.setInteractive(true):this.showWindow()));this.menu();
      this.watch=setInterval(()=>{if(this.active&&!this.restoring){try{if(!JSON.parse(this.native.wallpaperStatus(this.window.getNativeWindowHandle())).attached)this.native.attachWallpaper(this.window.getNativeWindowHandle());}catch(error){this.restore().catch(()=>{});this.notify(error.message);}}},2000);
      screen.on('display-metrics-changed',()=>{if(this.active)this.perform(()=>this.native.attachWallpaper(this.window.getNativeWindowHandle()));});
    }
    window.webContents.on('before-input-event',(event,input)=>{if(this.active&&input.type==='keyDown'&&input.key==='Escape'){event.preventDefault();this.perform(()=>this.setInteractive(false));}});
  }
  menu(){this.tray?.setContextMenu(Menu.buildFromTemplate([
    {label:'Use as Wallpaper',type:'checkbox',checked:this.active,enabled:!!this.native,click:()=>this.perform(()=>this.active?this.restore():this.attach())},
    {label:this.active?'Open Plaza in Window':'Show Plaza',click:()=>this.perform(()=>this.active?this.restore():this.showWindow())},
    {label:this.interactive?'Return to Desktop · Esc':'Interact with Plaza',enabled:this.active,click:()=>this.perform(()=>this.setInteractive(!this.interactive))},
    {type:'separator'},...['Mii Maker','Friends','Settings','Write Note','Activity','Miiverse'].map((label,i)=>({label,click:()=>this.perform(()=>this.panel(['maker','friends','settings','composer','activity','miiverse'][i]))})),
    {type:'separator'},{label:'Quit Plaza',click:()=>this.quit()}
  ]));}
  async attach(){if(!this.native)throw new Error('Wallpaper mode is available in the Windows build.');if(this.active)return;this.bounds=this.window.getBounds();this.native.attachWallpaper(this.window.getNativeWindowHandle());this.active=true;this.window.setSkipTaskbar(true);this.window.setMenuBarVisibility(false);this.window.showInactive();await this.setInteractive(this.settings.interactive!==false);this.settings.wallpaper=true;await this.save();this.menu();this.changed();}
  async restore(){if(!this.active)return;this.restoring=true;try{this.native.detachWallpaper(this.window.getNativeWindowHandle());this.window.setIgnoreMouseEvents(false);this.active=false;this.window.setSkipTaskbar(false);this.window.setMenuBarVisibility(true);if(this.bounds)this.window.setBounds(this.bounds);this.window.show();this.settings.wallpaper=false;await this.save();this.menu();this.changed();}finally{this.restoring=false;}}
  async setInteractive(value){this.interactive=!!value;this.window.setIgnoreMouseEvents(!this.interactive,{forward:true});if(this.interactive&&this.active){this.window.focus();this.window.webContents.focus();}this.settings.interactive=this.interactive;await this.save();this.menu();this.changed();}
  state(){return{supported:!!this.native,active:this.active,interactive:this.interactive};}
  changed(){this.window.webContents.send('plaza-wallpaper',this.state());}
  showWindow(){this.window.show();this.window.focus();}
  cleanup(){clearInterval(this.watch);if(this.active){try{this.native.detachWallpaper(this.window.getNativeWindowHandle());}catch{}}this.tray?.destroy();}
}
module.exports={Wallpaper};
