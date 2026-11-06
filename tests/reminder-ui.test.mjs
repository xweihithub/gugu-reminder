import test from 'node:test';import assert from 'node:assert/strict';import vm from 'node:vm';import fs from 'node:fs';

function harness({reducedMotion=false,reminderIntervals,legacyData={}}={}){
 let time=0,timers=[],frames=[],events={},regionCalls=[],calls={finish:[],resident:[],cinema:[],intervals:[]};
 const ids=['panel','close','notice','cinema','noticeCard','noticeTitle','noticeMessage','noticeEyebrow','noticeDone','noticeLater','noticeClose','noticeCharacter','restRing','restCount','restFill','reminderSettings','waterInterval','walkInterval','eyesInterval','saveIntervals','intervalStatus'];
 const elements=Object.fromEntries(ids.map(id=>{
  const classes=new Set(),style={setProperty(key,value){style[key]=value;}};
  return[id,{id,hidden:['panel','notice','noticeCard','noticeCharacter','restRing'].includes(id),style,dataset:{},value:'',checked:false,disabled:false,className:'',textContent:'',
   classList:{add:x=>classes.add(x),remove:x=>classes.delete(x),contains:x=>classes.has(x),toggle:(x,on)=>on?classes.add(x):classes.delete(x)},
   append(){},replaceChildren(){},querySelector(){return null;},focus(){},scrollIntoView(){},reportValidity(){return true;},setPointerCapture(){},setAttribute(key,value){this[key]=value;},
   getBoundingClientRect(){const x=parseFloat(this.style.left)||0,y=parseFloat(this.style.top)||0;return{x,y,left:x,top:y,width:parseFloat(this.style.width)||(this.id==='noticeCard'?282:this.id==='panel'?390:98),height:parseFloat(this.style.height)||(this.id==='noticeCard'?195:this.id==='panel'?400:106)};},
  }];
 }));
 const api={
  load:async()=>({...legacyData,reminderIntervals}),
  regions:v=>regionCalls.push(v),
  onEvent:fn=>{const old=events.agent;events.agent=e=>{old?.(e);fn(e);};},
  saveReminderIntervals:async values=>{calls.intervals.push(values);return{intervals:values,changed:Object.keys(values)};},
  finishReminder:async(kind,snooze)=>{calls.finish.push([kind,snooze]);},
 };
 const context={console,innerWidth:1512,innerHeight:900,performance:{now:()=>time},window:{paw:api,matchMedia:()=>({matches:reducedMotion}),PawCinema:{create:()=>({
   start:(kind,reduced)=>calls.cinema.push(['start',kind,reduced]),render:(t,phase,exit)=>calls.cinema.push(['render',t,phase,exit]),
   stop:()=>calls.cinema.push(['stop']),resize(){},hitRect:()=>({x:540,y:150,width:420,height:480}),
  })}},
  document:{body:{style:{}},getElementById:id=>elements[id],querySelectorAll:selector=>selector==='.interactive'?[elements.panel,elements.noticeCard,elements.noticeCharacter]:[],addEventListener:(name,fn)=>events[name]=fn,createElement:()=>({className:'',textContent:'',dataset:{},style:{},classList:{add(){},remove(){},toggle(){}},append(){},querySelector(){return null;}})},
  setTimeout:(fn,ms)=>{const t={fn,at:time+ms};timers.push(t);return t;},clearTimeout:t=>{timers=timers.filter(x=>x!==t);},
  setInterval:(fn,ms)=>{const t={fn,at:time+ms,repeat:ms};timers.push(t);return t;},clearInterval:t=>{timers=timers.filter(x=>x!==t);},
  requestAnimationFrame:fn=>frames.push(fn),confirm:()=>false};
 vm.createContext(context);vm.runInContext(fs.readFileSync(new URL('../src/renderer/app.js',import.meta.url),'utf8'),context);
 async function settle(){await Promise.resolve();await Promise.resolve();await Promise.resolve();}
 async function step(ms=50){
  time+=ms;const current=frames;frames=[];current.forEach(fn=>fn(time));
  const due=timers.filter(x=>x.at<=time).sort((a,b)=>a.at-b.at);timers=timers.filter(x=>x.at>time);
  due.forEach(x=>{x.fn();if(x.repeat){x.at=time+x.repeat;timers.push(x);}});
  await settle();
 }
 return {elements,events,step,ready:settle,regionCalls,calls,read:expr=>vm.runInContext(expr,context)};
}
const source=file=>fs.readFileSync(new URL(`../src/${file}`,import.meta.url),'utf8');

test('运行界面和桥接仅保留提醒与设置入口',()=>{
 const html=source('renderer/index.html'),js=source('renderer/app.js'),main=source('desktop/main.cjs'),bridge=source('desktop/preload.cjs');
 assert.doesNotMatch(html,/id="(?:pet|home|resident|pace|tasks|form|memory|waterPreview|walkPreview|eyesPreview)"|小金毛|golden-atlas/);
 assert.doesNotMatch(main,/叫它过来|任务与对话|平时待在右下角|立即提醒|本机控制台|隐藏咕咕嘎嘎|globalShortcut|PetAgent|ModelAdapter|ControlCenter/);
 assert.doesNotMatch(bridge,/previewReminder|saveResident|savePace|saveHome|remember|openControl|paw:run|paw:cancel/);
 assert.doesNotMatch(js,/summon|followArmed|restorePresence|returnHome/);
 assert.match(main,/show:false/);assert.match(main,/backgroundThrottling:false/);
 assert.equal(fs.readdirSync(new URL('../src/core/',import.meta.url)).join(','),'reminders.cjs');
});

test('启动与旧常驻存档都不会显示角色或设置',async()=>{
 const h=harness({legacyData:{resident:true,home:{x:10,y:10},history:[],preferences:['安静']}});await h.ready();
 assert.equal(h.elements.notice.hidden,true);assert.equal(h.elements.panel.hidden,true);
 assert.equal(h.regionCalls.at(-1).length,0);assert.deepEqual(h.calls.cinema,[]);
 h.events.agent({kind:'summon'});h.events.agent({kind:'resident',resident:true});
 assert.equal(h.elements.notice.hidden,true);assert.deepEqual(h.calls.cinema,[]);
});

async function arrive(h){for(let i=0;i<60;i++)await h.step(50);}
async function leave(h){for(let i=0;i<28;i++)await h.step(50);}

test('三类到期事件各自播放专属动画，入场后显示提示',async()=>{
 for(const kind of ['water','walk','eyes']){
  const h=harness();await h.ready();h.events.agent({kind:'reminder',reminder:kind});
  assert.equal(h.elements.notice.hidden,false);assert.equal(h.elements.noticeCard.hidden,true);
  assert.deepEqual(h.calls.cinema[0],['start',kind,false]);
  await arrive(h);assert.equal(h.elements.noticeCard.hidden,false);
  assert.equal(h.elements.restRing.hidden,kind!=='eyes');assert.equal(h.elements.noticeDone.disabled,kind==='eyes');
  assert.ok(h.calls.cinema.some(c=>c[0]==='render'&&c[2]==='performing'));
 }
});

test('回应只完成一次，淡出后桌面不保留角色和点击区域',async()=>{
 const h=harness();await h.ready();h.events.agent({kind:'reminder',reminder:'water'});await arrive(h);
 h.elements.noticeDone.onclick();h.elements.noticeCharacter.onclick();await h.ready();
 assert.deepEqual(h.calls.finish,[['water',false]]);assert.equal(h.read('healthStage'),'leaving');
 assert.equal(h.elements.noticeCard.hidden,true);await leave(h);
 assert.equal(h.elements.notice.hidden,true);assert.equal(h.read('currentHealth'),null);
 assert.equal(h.calls.cinema.at(-1)[0],'stop');assert.equal(h.regionCalls.at(-1).length,0);
});

test('眼睛休息从入场结束计时二十秒，完成后自动收起',async()=>{
 const h=harness();await h.ready();h.events.agent({kind:'reminder',reminder:'eyes'});await arrive(h);
 const start=h.read('healthStarted');assert.ok(start>=2650);
 h.elements.noticeDone.onclick();assert.deepEqual(h.calls.finish,[]);
 while(h.read('performance.now()')-start<10000)await h.step(50);
 assert.equal(h.elements.restCount.textContent,'10');assert.equal(h.elements.noticeDone.disabled,true);
 while(h.read('performance.now()')-start<20000)await h.step(50);
 assert.equal(h.elements.restCount.textContent,'✓');assert.equal(h.elements.noticeDone.disabled,false);
 for(let i=0;i<60;i++)await h.step(50);
 assert.equal(h.elements.notice.hidden,true);assert.deepEqual(h.calls.finish,[['eyes',false]]);
});

test('喝水和走动无人回应时收起，重复到期事件不重启动画',async()=>{
 for(const kind of ['water','walk']){
  const h=harness();await h.ready();h.events.agent({kind:'reminder',reminder:kind});await arrive(h);
  const start=h.read('healthStarted');h.events.agent({kind:'reminder',reminder:kind});
  assert.equal(h.read('healthStarted'),start);assert.equal(h.calls.cinema.filter(c=>c[0]==='start').length,1);
  for(let i=0;i<160;i++)await h.step(50);
  assert.equal(h.elements.notice.hidden,true);assert.deepEqual(h.calls.finish,[[kind,false]]);
 }
});

test('只有稍后请求短时重排，关闭与 Esc 使用正常间隔',async()=>{
 const h=harness();await h.ready();h.events.agent({kind:'reminder',reminder:'walk'});await arrive(h);
 assert.equal(h.elements.noticeLater['aria-label'],'10 分钟后提醒');
 h.elements.noticeLater.onclick();await h.ready();await leave(h);
 h.events.agent({kind:'reminder',reminder:'water'});await arrive(h);h.elements.noticeClose.onclick();await h.ready();await leave(h);
 h.events.agent({kind:'reminder',reminder:'eyes'});await arrive(h);
 assert.equal(h.elements.noticeLater['aria-label'],'5 分钟后提醒');
 h.events.keydown({key:'Escape'});await h.ready();await leave(h);
 assert.deepEqual(h.calls.finish,[['walk',true],['water',false],['eyes',false]]);
});

test('暂停清除播放与旧计时器，不残留提醒或额外确认',async()=>{
 const h=harness();await h.ready();h.events.agent({kind:'reminder',reminder:'eyes'});await arrive(h);
 h.events.agent({kind:'reminder-dismiss'});for(let i=0;i<520;i++)await h.step(50);
 assert.equal(h.elements.notice.hidden,true);assert.deepEqual(h.calls.finish,[]);assert.equal(h.regionCalls.at(-1).length,0);
});

test('设置打开时延后到期动画，关闭后再播放',async()=>{
 const h=harness();await h.ready();h.events.agent({kind:'reminder-settings-open'});await h.ready();
 assert.equal(h.elements.panel.hidden,false);assert.deepEqual(h.calls.cinema,[]);
 h.events.agent({kind:'reminder',reminder:'eyes'});assert.equal(h.read('pendingHealth'),'eyes');
 assert.equal(h.elements.notice.hidden,true);h.elements.close.onclick();await h.step(1000);
 assert.equal(h.read('currentHealth'),'eyes');assert.equal(h.elements.notice.hidden,false);
});

test('提醒中打开设置会正常结束本次，之后不残留动画',async()=>{
 const h=harness();await h.ready();h.events.agent({kind:'reminder',reminder:'water'});await arrive(h);
 h.events.agent({kind:'reminder-settings-open'});await h.ready();
 assert.equal(h.elements.panel.hidden,false);assert.equal(h.elements.notice.hidden,true);
 assert.deepEqual(h.calls.finish,[['water',false]]);h.events.keydown({key:'Escape'});
 assert.equal(h.elements.panel.hidden,true);assert.equal(h.regionCalls.at(-1).length,0);
});

test('只有动画角色和提示接收点击，其余桌面穿透',async()=>{
 const h=harness();await h.ready();h.events.agent({kind:'reminder',reminder:'water'});await arrive(h);
 const last=h.regionCalls.at(-1);assert.equal(last.length,2);
 assert.equal(last[0].width,282);assert.equal(last[1].width,420);
});

test('减少动态效果模式直接显示静帧，保留提示与休息计时',async()=>{
 const h=harness({reducedMotion:true});await h.ready();h.events.agent({kind:'reminder',reminder:'walk'});await h.step(16);
 assert.equal(h.read('healthStage'),'ready');assert.deepEqual(h.calls.cinema[0],['start','walk',true]);
 h.elements.noticeCharacter.onclick();await h.ready();assert.equal(h.elements.notice.hidden,true);
 h.events.agent({kind:'reminder',reminder:'eyes'});await h.step(16);await h.step(10000);
 assert.equal(h.elements.restCount.textContent,'10');assert.equal(h.elements.noticeDone.disabled,true);
});

test('设置加载已存间隔，保存三项修改并反馈结果',async()=>{
 const h=harness({reminderIntervals:{water:30,walk:45,eyes:20}});await h.ready();
 assert.equal(h.elements.waterInterval.value,30);assert.equal(h.elements.eyesInterval.value,20);
 h.elements.waterInterval.value='35';h.elements.walkInterval.value='55';h.elements.eyesInterval.value='25';
 await h.elements.reminderSettings.onsubmit({preventDefault(){}});
 assert.deepEqual(JSON.parse(JSON.stringify(h.calls.intervals)),[{water:35,walk:55,eyes:25}]);
 assert.match(h.elements.intervalStatus.textContent,/已保存/);assert.equal(h.elements.saveIntervals.disabled,false);
});

test('更改设置取消该类旧排队提醒，不立即播放',async()=>{
 const h=harness();await h.ready();h.events.agent({kind:'reminder-settings-open'});await h.ready();
 h.events.agent({kind:'reminder',reminder:'eyes'});assert.equal(h.read('pendingHealth'),'eyes');
 h.events.agent({kind:'reminder-settings',intervals:{water:60,walk:50,eyes:30},changed:['eyes']});
 h.elements.close.onclick();await h.step(2000);assert.equal(h.read('pendingHealth'),null);assert.equal(h.read('currentHealth'),null);
});
