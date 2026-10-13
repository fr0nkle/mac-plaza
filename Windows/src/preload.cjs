const { contextBridge, ipcRenderer } = require('electron');
contextBridge.exposeInMainWorld('plaza', { call: async (action, value) => {
  const result = await ipcRenderer.invoke('plaza', action, value);
  if (!result.ok) throw new Error(result.error);
  return result.value;
} });
