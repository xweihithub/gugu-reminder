// 运行实际主进程与 preload；设置只写入临时目录，不修改用户偏好。
const {app}=require('electron');
const fs=require('node:fs'),path=require('node:path'),os=require('node:os'),assert=require('node:assert/strict');
const root=fs.mkdtempSync(path.join(os.tmpdir(),'golden-paw-settings-qa-'));
app.setPath('userData',root);
app.on('browser-window-created',(_e,win)=>{
 win.hide();win.webContents.once('did-finish-load',async()=>{
  try{
   await win.webContents.executeJavaScript(`(async()=>{
    await new Promise(r=>setTimeout(r,100));showSettings();
    document.querySelector('#waterInterval').value='30';document.querySelector('#walkInterval').value='45';document.querySelector('#eyesInterval').value='20';
    document.querySelector('#reminderSettings').requestSubmit();
    const deadline=Date.now()+3000;while(!document.querySelector('#intervalStatus').textContent.includes('已保存')){if(Date.now()>deadline)throw Error('保存超时');await new Promise(r=>setTimeout(r,20));}
   })()`);
   const persisted=JSON.parse(fs.readFileSync(path.join(root,'state.json'),'utf8'));
   assert.deepEqual(persisted.reminders.intervals,{eyes:20,walk:45,water:30});
   const invalidRejected=await win.webContents.executeJavaScript(`window.paw.saveReminderIntervals({water:0}).then(()=>false,()=>true)`);
   assert.equal(invalidRejected,true);assert.equal(JSON.parse(fs.readFileSync(path.join(root,'state.json'),'utf8')).reminders.intervals.water,30);
   const reloaded=new Promise(r=>win.webContents.once('did-finish-load',r));win.webContents.reload();await reloaded;
   const loaded=await win.webContents.executeJavaScript(`(async()=>{await new Promise(r=>setTimeout(r,100));showSettings();document.querySelector('#reminderSettings').scrollIntoView({block:'center'});return Object.fromEntries(['water','walk','eyes'].map(k=>[k,Number(document.querySelector('#'+k+'Interval').value)]));})()`);
   assert.deepEqual(loaded,{water:30,walk:45,eyes:20});
   for(const paused of [true,false]){
    await win.webContents.executeJavaScript(`document.querySelector('#pauseReminders').click()`);
    const deadline=Date.now()+2000;
    while(await win.webContents.executeJavaScript(`document.querySelector('#pauseReminders').dataset.paused`)!==String(paused)){if(Date.now()>deadline)throw Error('暂停状态同步超时');await new Promise(r=>setTimeout(r,30));}
    assert.equal(JSON.parse(fs.readFileSync(path.join(root,'state.json'),'utf8')).reminders.pausedUntil>Date.now(),paused);
   }
   await win.webContents.executeJavaScript('document.fonts.ready.then(()=>true)');
   win.showInactive();await new Promise(r=>setTimeout(r,250));
   const rect=await win.webContents.executeJavaScript(`(()=>{const r=document.querySelector('#panel').getBoundingClientRect();return{x:Math.floor(r.x),y:Math.floor(r.y),width:Math.ceil(r.width),height:Math.ceil(r.height)};})()`);
   fs.mkdirSync(path.resolve('artifacts/settings'),{recursive:true});fs.writeFileSync(path.resolve('artifacts/settings/settings-qa.png'),(await win.webContents.capturePage(rect)).toPNG());
   console.log(JSON.stringify({saved:persisted.reminders.intervals,reloaded:loaded,invalidRejected},null,2));
   // Windows 的 Chromium 会话文件在进程退出前可能保持锁定。
   try{fs.rmSync(root,{recursive:true,force:true});}catch(error){if(process.platform!=='win32'||!['EPERM','EBUSY','ENOTEMPTY'].includes(error.code))throw error;}
   app.exit(0);
  }catch(error){console.error(error);app.exit(1);}
 });
});
require('../src/desktop/main.cjs');
setTimeout(()=>{console.error('设置验证超时');app.exit(1);},15000).unref();
