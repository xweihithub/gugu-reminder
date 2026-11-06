// 使用真实主进程、存档、计时器与菜单；测试数据独立于用户存档。
const {app,Menu,globalShortcut}=require('electron');
const fs=require('node:fs'),path=require('node:path'),os=require('node:os'),assert=require('node:assert/strict');
const root=fs.mkdtempSync(path.join(os.tmpdir(),'gugugaga-scheduled-qa-'));
const mainFile=path.resolve(process.env.GOLDEN_PAW_QA_MAIN||'src/desktop/main.cjs');
const kind=process.env.GOLDEN_PAW_QA_KIND||'water';
assert.ok(['water','walk','eyes'].includes(kind));
const now=Date.now(),deadline=now+5000;
const seed={resident:true,home:{x:20,y:20},preferences:['旧版偏好'],history:[],reminders:{intervals:{water:60,walk:50,eyes:40},next:{water:now+3600000,walk:now+3600000,eyes:now+3600000}}};
seed.reminders.next[kind]=deadline;
fs.writeFileSync(path.join(root,'state.json'),JSON.stringify(seed));app.setPath('userData',root);
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
app.on('browser-window-created',(_e,win)=>{
 let showed=0;win.on('show',()=>{showed++;win.hide();});
 win.webContents.once('did-finish-load',async()=>{
  try{
   await delay(100);
   const startup=await win.webContents.executeJavaScript(`({noticeHidden:document.querySelector('#notice').hidden,settingsHidden:document.querySelector('#panel').hidden,oldCharacter:!!document.querySelector('#pet,#home'),api:Object.keys(window.paw)})`);
   assert.ok(startup.noticeHidden&&startup.settingsHidden&&!startup.oldCharacter);
   assert.equal(showed,0);assert.equal(globalShortcut.isRegistered('CommandOrControl+Alt+P'),false);
   assert.deepEqual(startup.api.sort(),['load','regions','finishReminder','saveReminderIntervals','onEvent'].sort());
   const menu=Menu.getApplicationMenu(),labels=menu.items[0].submenu.items.filter(item=>item.type!=='separator').map(item=>item.label);
   assert.deepEqual(labels,['提醒设置','暂停提醒 1 小时','恢复提醒','退出']);
   menu.getMenuItemById('reminder-settings').click();await delay(100);
   assert.equal(await win.webContents.executeJavaScript(`document.querySelector('#panel').hidden`),false);
   const out=path.resolve('artifacts/reminder-only');fs.mkdirSync(out,{recursive:true});
   const rect=await win.webContents.executeJavaScript(`(()=>{const r=document.querySelector('#panel').getBoundingClientRect();return{x:Math.floor(r.x),y:Math.floor(r.y),width:Math.ceil(r.width),height:Math.ceil(r.height)};})()`);
   fs.writeFileSync(path.join(out,'settings.png'),(await win.webContents.capturePage(rect)).toPNG());
   await win.webContents.executeJavaScript(`document.querySelector('#close').click()`);
   assert.ok(Date.now()<deadline,'启动与设置检查必须在提醒到期前完成');
   while(Date.now()<deadline+8000){
    if(await win.webContents.executeJavaScript(`document.querySelector('#notice').dataset.phase==='performing'`))break;
    await delay(100);
   }
   const playback=await win.webContents.executeJavaScript(`(()=>{
    const v=document.querySelector('#cinema video'),c=document.createElement('canvas');c.width=c.height=1080;
    const ctx=c.getContext('2d',{willReadFrequently:true});ctx.drawImage(v,0,0);const data=ctx.getImageData(0,0,1080,1080).data;
    let clear=0,opaque=0;for(let i=3;i<data.length;i+=4){if(data[i]===0)clear++;if(data[i]===255)opaque++;}
    return{source:v.currentSrc,time:v.currentTime,error:v.error?.message||null,clear,opaque,visible:!document.querySelector('#noticeCard').hidden};
   })()`);
   assert.ok(playback.source.endsWith('gugugaga-'+kind+'-alpha.webm'));
   assert.ok(playback.time>2&&!playback.error&&playback.visible&&playback.clear>50000&&playback.opaque>50000);
   assert.ok(showed>=2,'菜单打开设置和计时到期均应显示窗口');
   menu.getMenuItemById('reminder-pause').click();await delay(100);
   assert.equal(await win.webContents.executeJavaScript(`document.querySelector('#notice').hidden&&document.querySelector('#cinema video').paused`),true);
   const paused=JSON.parse(fs.readFileSync(path.join(root,'state.json'),'utf8'));
   assert.ok(paused.reminders.pausedUntil>Date.now());assert.equal(paused.preferences[0],'旧版偏好');
   menu.getMenuItemById('reminder-resume').click();await delay(100);
   const resumed=JSON.parse(fs.readFileSync(path.join(root,'state.json'),'utf8'));
   assert.equal(resumed.reminders.pausedUntil,0);assert.ok(resumed.reminders.next[kind]>Date.now());
   const report={startup,labels,kind,scheduledPlayback:playback,pauseAndResume:true,legacyDataPreserved:true};
   fs.writeFileSync(path.join(out,'scheduled-'+kind+'-qa.json'),JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));
   fs.rmSync(root,{recursive:true,force:true});app.exit(0);
  }catch(error){console.error(error);app.exit(1);}
 });
});
require(mainFile);
setTimeout(()=>{console.error('定时提醒验证超时');app.exit(1);},22000).unref();
