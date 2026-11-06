// 在真实 Electron 解码器中核实透明通道、完整播放、切换素材和休息计时。
const {app,BrowserWindow,ipcMain}=require('electron');
const path=require('node:path'),fs=require('node:fs');
const rendererRoot=path.resolve(process.env.GOLDEN_PAW_QA_RENDERER||'src/renderer');
const reminderKind=process.env.GOLDEN_PAW_QA_KIND||'water';
if(!['water','walk','eyes'].includes(reminderKind))throw Error('未知提醒类型');
const delay=ms=>new Promise(r=>setTimeout(r,ms));
app.setName('Golden Paw Video QA');
app.commandLine.appendSwitch('autoplay-policy','no-user-gesture-required');
app.whenReady().then(async()=>{
 let win;try{
  const finished=[];let regions=[];
  ipcMain.handle('paw:load',()=>({}));
  ipcMain.on('paw:regions',(_e,r)=>regions=r);
  ipcMain.handle('paw:reminder-finish',(_e,kind,snooze)=>finished.push({kind,snooze}));
  win=new BrowserWindow({show:false,width:1100,height:940,transparent:true,frame:false,webPreferences:{preload:path.resolve(rendererRoot,'../desktop/preload.cjs'),contextIsolation:true,nodeIntegration:false,sandbox:true,backgroundThrottling:false}});
  await win.loadFile(path.join(rendererRoot,'index.html'));
  await win.webContents.executeJavaScript(`(async()=>{
   const v=document.querySelector('#cinema video');
   if(v.readyState<2)await new Promise((resolve,reject)=>{v.addEventListener('loadeddata',resolve,{once:true});v.addEventListener('error',()=>reject(new Error('视频解码失败')),{once:true});});
   healthReminder(${JSON.stringify(reminderKind)});
  })()`);
  await delay(3600);
  const playback=await win.webContents.executeJavaScript(`(()=>{
   const v=document.querySelector('#cinema video'),c=document.createElement('canvas');c.width=c.height=1080;
   const x=c.getContext('2d',{willReadFrequently:true});x.drawImage(v,0,0,1080,1080);const d=x.getImageData(0,0,1080,1080).data;
   let clear=0,opaque=0;for(let i=3;i<d.length;i+=4){if(d[i]===0)clear++;if(d[i]===255)opaque++;}
   return{time:v.currentTime,duration:v.duration,error:v.error?.message||null,clear,opaque,corners:[d[3],d[1079*4+3],d[(1080*1080-1)*4+3]],phase:document.querySelector('#notice').dataset.phase,cardVisible:!document.querySelector('#noticeCard').hidden,source:v.currentSrc};
  })()`);
  if(playback.error||playback.time<2||playback.clear<50000||playback.opaque<50000||playback.corners.some(Boolean)||!playback.cardVisible||!playback.source.endsWith(`gugugaga-${reminderKind}-alpha.webm`))throw Error('播放或 alpha 验证失败：'+JSON.stringify(playback));
  const out=path.resolve('artifacts/reminders/film/outputs');fs.mkdirSync(out,{recursive:true});
  await delay(4600);
  const end=await win.webContents.executeJavaScript(`({ended:document.querySelector('#cinema video').ended,time:document.querySelector('#cinema video').currentTime,visible:!document.querySelector('#notice').hidden})`);
  if(!end.ended||!end.visible)throw Error('完整片段未正常结束和停留');
  fs.writeFileSync(path.join(out,`electron-${reminderKind}-transparent-proof.png`),(await win.webContents.capturePage()).toPNG());
  let eyesCompletion=null;
  if(reminderKind==='eyes'){
   await delay(14600);
   eyesCompletion=await win.webContents.executeJavaScript(`({ready:!document.querySelector('#noticeDone').disabled,count:document.querySelector('#restCount').textContent,title:document.querySelector('#noticeTitle').textContent,visible:!document.querySelector('#notice').hidden})`);
   if(!eyesCompletion.ready||eyesCompletion.count!=='✓'||!eyesCompletion.visible)throw Error('眼睛休息倒计时未正确完成');
  }
  await win.webContents.executeJavaScript(`finishHealth(false,{animate:false})`);
  const dismissed=await win.webContents.executeJavaScript(`document.querySelector('#notice').hidden&&document.querySelector('#cinema video').paused`);
  if(!dismissed||finished.length!==1||finished[0].kind!==reminderKind)throw Error('完成提醒未正确停止视频');
  const nextKind=reminderKind==='eyes'?'water':'eyes';
  await win.webContents.executeJavaScript(`healthReminder(${JSON.stringify(nextKind)})`);
  await delay(2900);
  const switched=await win.webContents.executeJavaScript(`({videoHidden:document.querySelector('#cinema video').hidden,stillVisible:!document.querySelector('#cinema img').hidden,time:document.querySelector('#cinema video').currentTime,source:document.querySelector('#cinema video').currentSrc,phase:document.querySelector('#notice').dataset.phase})`);
  if(switched.videoHidden||switched.stillVisible||switched.time<2||switched.phase!=='performing'||!switched.source.endsWith(`gugugaga-${nextKind}-alpha.webm`))throw Error('提醒切换未播放对应素材');
  await win.webContents.executeJavaScript(`dismissNotice(); healthReminder(${JSON.stringify(reminderKind)})`);
  await delay(500);
  const restart=await win.webContents.executeJavaScript(`document.querySelector('#cinema video').currentTime`);
  if(restart<.1||restart>1.5)throw Error('再次播放没有从头开始');
  const report={playback,end,eyesCompletion,dismissed,switched,restart,interactiveRegions:regions.length};
  fs.writeFileSync(path.join(out,`electron-${reminderKind}-video-qa.json`),JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));
  win.destroy();app.exit(0);
 }catch(error){console.error(error);win?.destroy();app.exit(1);}
});
setTimeout(()=>{console.error('视频验证超时');app.exit(1);},40000).unref();
