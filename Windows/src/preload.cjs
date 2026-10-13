const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('plaza', { call: async (action, value) => {
  const result = await ipcRenderer.invoke('plaza', action, value);
  if (!result.ok) throw new Error(result.error);
  return result.value;
},frame:args=>ipcRenderer.invoke('plaza-frame',args),subscribe:(name,callback)=>{
  if(!['plaza-state','plaza-snapshot','plaza-wallpaper','plaza-environment','plaza-error','plaza-music-role','plaza-panel-context'].includes(name))throw new Error('Unknown event.');
  const listener=(_event,value)=>callback(value);ipcRenderer.on(name,listener);return()=>ipcRenderer.removeListener(name,listener);
} });
