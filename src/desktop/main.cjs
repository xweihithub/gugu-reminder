const {app,BrowserWindow,ipcMain,screen,Menu,Tray,nativeImage,powerMonitor}=require('electron');
const path=require('node:path'),fs=require('node:fs');
const {ReminderClock}=require('../core/reminders.cjs');
// 保留存储标识，继续使用既有提醒设置；旧陪伴和助理字段不再参与运行。
app.setName('Golden Paw');
let win,tray,rects=[],storeFile,reminders,hitTimer,reminderTimer,ignore=true,announcedReminder=null,saved={};
if(!app.requestSingleInstanceLock())app.quit();
app.on('second-instance',()=>openSettings());
function persist(){saved.reminders=reminders.snapshot();fs.mkdirSync(path.dirname(storeFile),{recursive:true});fs.writeFileSync(storeFile+'.tmp',JSON.stringify(saved,null,2),{mode:0o600});fs.renameSync(storeFile+'.tmp',storeFile);}
function send(data){if(win&&!win.isDestroyed())win.webContents.send('paw:event',data);}
function visible(){if(!win||win.isDestroyed())return;win.showInactive();win.moveTop();}
function openSettings(){if(!win||win.isDestroyed())return;visible();win.focus();send({kind:'reminder-settings-open'});}
function bounds(){return screen.getPrimaryDisplay().workArea;}
function layout(){win.setBounds(bounds());rects=[];send({kind:'layout'});}
function setPaused(paused){
 if(paused){reminders.pause();send({kind:'reminder-dismiss'});}else reminders.reset();
 announcedReminder=null;persist();const state={pausedUntil:reminders.pausedUntil};send({kind:'reminder-state',...state});return state;
}
function menuItems(){return[
  {id:'reminder-settings',label:'提醒设置',click:openSettings},
  {id:'reminder-pause',label:'暂停提醒 1 小时',click:()=>setPaused(true)},
  {id:'reminder-resume',label:'恢复提醒',click:()=>setPaused(false)},
  {type:'separator'},
  {label:'退出',click:()=>app.quit()}
];}
app.whenReady().then(async()=>{
  if(!app.hasSingleInstanceLock())return;
  storeFile=path.join(app.getPath('userData'),'state.json');
  try{const data=JSON.parse(fs.readFileSync(storeFile,'utf8'));if(data&&typeof data==='object'&&!Array.isArray(data))saved=data;}catch{}
  reminders=new ReminderClock(saved.reminders);persist();
  win=new BrowserWindow({...bounds(),show:false,transparent:true,frame:false,resizable:false,hasShadow:false,alwaysOnTop:true,skipTaskbar:true,title:'咕咕嘎嘎 · 定时提醒',webPreferences:{preload:path.join(__dirname,'preload.cjs'),contextIsolation:true,nodeIntegration:false,sandbox:true,backgroundThrottling:false}});
  if(process.platform==='darwin')win.setVisibleOnAllWorkspaces(true,{visibleOnFullScreen:true});
  win.setIgnoreMouseEvents(true,{forward:true});
  win.webContents.setWindowOpenHandler(()=>({action:'deny'}));win.webContents.on('will-navigate',e=>e.preventDefault());
  await win.loadFile(path.join(__dirname,'../renderer/index.html'));
  reminderTimer=setInterval(()=>{if(reminders.pausedUntil&&reminders.pausedUntil<=Date.now()){reminders.pausedUntil=0;persist();send({kind:'reminder-state',pausedUntil:0});}const due=reminders.due();if(due){if(due!==announcedReminder)visible();send({kind:'reminder',reminder:due});}announcedReminder=due;},1000);
  powerMonitor.on('resume',()=>{reminders.reset();announcedReminder=null;persist();send({kind:'reminder-dismiss'});send({kind:'reminder-state',pausedUntil:0});});
  hitTimer=setInterval(()=>{
    if(!win||win.isDestroyed())return;
    const p=screen.getCursorScreenPoint(),b=win.getBounds(),x=p.x-b.x,y=p.y-b.y;
    const hit=rects.some(r=>x>=r.x&&x<=r.x+r.width&&y>=r.y&&y<=r.y+r.height);
    if(ignore===hit){ignore=!hit;win.setIgnoreMouseEvents(ignore,{forward:true});}
  },30);
  const icon=nativeImage.createFromPath(path.join(__dirname,'icons/gugu.png')).resize({width:process.platform==='darwin'?20:32});
  tray=new Tray(icon);
  if(process.platform==='darwin')tray.setTitle('🐧');
  tray.setToolTip('咕咕提醒 · 喝水、走动、眼睛休息');tray.setContextMenu(Menu.buildFromTemplate(menuItems()));
  tray.on('click',openSettings);
  tray.on('double-click',openSettings);
  Menu.setApplicationMenu(Menu.buildFromTemplate([{label:app.name,submenu:menuItems()},{role:'editMenu'}]));
  screen.on('display-metrics-changed',layout);screen.on('display-removed',layout);screen.on('display-added',layout);
  app.dock?.hide();
});
app.on('before-quit',()=>{clearInterval(hitTimer);clearInterval(reminderTimer);});
app.on('window-all-closed',()=>app.quit());
ipcMain.handle('paw:load',()=>({reminderIntervals:{...reminders.intervals},pausedUntil:reminders.pausedUntil}));
ipcMain.on('paw:regions',(_e,v)=>{if(Array.isArray(v))rects=v.filter(r=>r&&['x','y','width','height'].every(k=>Number.isFinite(r[k]))&&r.width>0&&r.height>0).slice(0,20);});
ipcMain.handle('paw:reminder-finish',(_e,kind,snooze)=>{
  if(!['water','eyes','walk'].includes(kind))return;
  reminders.finish(kind,Boolean(snooze));announcedReminder=null;persist();
});
ipcMain.handle('paw:reminder-intervals',(_e,values)=>{
  const changed=reminders.setIntervals(values);persist();announcedReminder=null;
  const result={intervals:{...reminders.intervals},changed};send({kind:'reminder-settings',...result});return result;
});

ipcMain.handle('paw:pause',(_e,paused)=>{if(typeof paused!=='boolean')throw Error('无效暂停参数');return setPaused(paused);});
ipcMain.on('paw:quit',()=>app.quit());
