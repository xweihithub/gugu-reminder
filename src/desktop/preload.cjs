const {contextBridge,ipcRenderer}=require('electron');
contextBridge.exposeInMainWorld('paw',{
  load:()=>ipcRenderer.invoke('paw:load'),
  regions:rects=>ipcRenderer.send('paw:regions',rects),
  finishReminder:(kind,snooze)=>ipcRenderer.invoke('paw:reminder-finish',kind,snooze),
  saveReminderIntervals:values=>ipcRenderer.invoke('paw:reminder-intervals',values),
  onEvent:fn=>{const handler=(_e,data)=>fn(data);ipcRenderer.on('paw:event',handler);return ()=>ipcRenderer.removeListener('paw:event',handler);}
});
