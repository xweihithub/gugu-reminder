const {app,BrowserWindow,ipcMain}=require('electron');
const path=require('node:path'),fs=require('node:fs'),assert=require('node:assert/strict');
app.setName('Gugu Layout QA');
app.whenReady().then(async()=>{
 let win;
 try{
  ipcMain.handle('paw:load',()=>({}));ipcMain.on('paw:regions',()=>{});
  ipcMain.handle('paw:reminder-finish',()=>{});
  win=new BrowserWindow({show:false,frame:false,webPreferences:{offscreen:true,preload:path.resolve('src/desktop/preload.cjs'),backgroundThrottling:false}});
  await win.loadFile(path.resolve('src/renderer/index.html'));
  await win.webContents.executeJavaScript('document.fonts.ready.then(()=>true)');
  const report=[];
  for(const [width,height] of [[1280,680],[1366,728],[1920,1040],[2560,1400]]){
   win.setContentSize(width,height);
   for(const kind of ['water','walk','eyes']){
    await win.webContents.executeJavaScript(`dismissNotice();healthReminder('${kind}')`);
    await new Promise(r=>setTimeout(r,150));
    const entry=await win.webContents.executeJavaScript(`(()=>{const r=document.querySelector('#cinema').getBoundingClientRect();return {x:r.x,y:r.y,width:r.width,height:r.height};})()`);
    await new Promise(r=>setTimeout(r,2700));
    const layout=await win.webContents.executeJavaScript(`(()=>{const rect=id=>{const r=document.querySelector(id).getBoundingClientRect();return{x:r.x,y:r.y,width:r.width,height:r.height};};return{width:innerWidth,height:innerHeight,cinema:rect('#cinema'),card:rect('#noticeCard'),visible:!document.querySelector('#noticeCard').hidden};})()`);
    assert.ok(layout.visible);
    for(const r of [layout.cinema,layout.card]){assert.ok(r.x>=0&&r.y>=0);assert.ok(r.x+r.width<=layout.width+1&&r.y+r.height<=layout.height+1);}
    assert.ok(layout.cinema.y+layout.cinema.height<=layout.card.y,'动画与提示不重叠');
    assert.ok(layout.card.y-(layout.cinema.y+layout.cinema.height)<=12,'提示紧跟画面，不出现大段空白');
    assert.ok(layout.cinema.y>=24,'视频顶部保留屏幕安全距离');
    assert.ok(Math.abs(layout.cinema.width-layout.cinema.height)<1,'视频容器保持正方形，消除 contain 产生的上下留白');
    assert.ok(Math.abs(entry.height-layout.cinema.height)<1,'入场和提示出现后尺寸保持稳定');
    report.push({kind,...layout});
    if(width===1920&&kind==='water'){
     fs.mkdirSync('artifacts/layout',{recursive:true});fs.writeFileSync('artifacts/layout/water-1920.png',(await win.webContents.capturePage()).toPNG());
    }
   }
  }
  fs.mkdirSync('artifacts/layout',{recursive:true});fs.writeFileSync('artifacts/layout/report.json',JSON.stringify(report,null,2));
  console.log('通过：4 种显示区域 × 3 类动画，无越界、无重叠、入场尺寸稳定');win.destroy();app.exit(0);
 }catch(error){console.error(error);win?.destroy();app.exit(1);}
});
setTimeout(()=>app.exit(1),60000).unref();
