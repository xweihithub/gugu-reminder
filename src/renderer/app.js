const $=id=>document.getElementById(id);
const api=window.paw,panel=$('panel');
let pendingHealth=null,currentHealth=null,noticeTimer,healthStarted=0,healthStage='none',shownCount=null;
let healthAnimation=0,healthX=0,healthY=0,cinema=null,shotStarted=0;
const reducedMotion=()=>window.matchMedia?.('(prefers-reduced-motion: reduce)').matches||false;
function regions(){
 api.regions([...document.querySelectorAll('.interactive')].filter(e=>!e.hidden).map(e=>{const r=e.getBoundingClientRect();return{x:r.x,y:r.y,width:r.width,height:r.height};}).filter(r=>r.width>0&&r.height>0));
}
async function showSettings(){
 if(currentHealth)await finishHealth(false,{animate:false});
 panel.hidden=false;regions();$('waterInterval').focus();
}
$('close').onclick=()=>{panel.hidden=true;regions();};
const healthCopy={
 water:{title:'咕噜咕噜，喝水啦～',message:'我也喝一口，陪你一起。',done:'喝好啦',later:'10 分钟后',label:'喝水提醒'},
 walk:{title:'走走呀，舒展一下～',message:'放下手里的事，陪我走几步？',done:'这就起来',later:'10 分钟后',label:'走动提醒'},
 eyes:{title:'眨眨眼，看向远处～',message:'看看远处，慢慢眨眼。我陪你数 20 秒。',done:'休息中…',later:'5 分钟后',label:'眼睛休息'},
};
function ensureCinema(){
 if(cinema)return cinema;
 try{cinema=window.PawCinema.create($('cinema'));return cinema;}
 catch(error){console.error('提醒视频初始化失败',error);return null;}
}
function positionNotice(){
 const card=$('noticeCard');card.style.left='';card.style.top='';
}
function drawCinema(time,phase='entering',exit=0){
 if(!cinema)return;
 cinema.render(time,phase,exit);
 const r=cinema.hitRect();healthX=r.x;healthY=r.y;
 const character=$('noticeCharacter');character.style.left=r.x+'px';character.style.top=r.y+'px';character.style.width=r.width+'px';character.style.height=r.height+'px';
}
function updateHealth(now){
 const elapsed=now-healthStarted;drawCinema((now-shotStarted)/1000,'performing');
 if(currentHealth!=='eyes')return;
 const ready=elapsed>=20000,left=Math.max(0,Math.ceil((20000-elapsed)/1000));
 if(shownCount!==left){shownCount=left;$('restCount').textContent=ready?'✓':String(left);}
 $('restFill').style.width=`${Math.min(100,elapsed/200)}%`;
 if(ready&&healthStage!=='ready'){
  healthStage='ready';$('noticeCard').dataset.stage='ready';$('noticeDone').disabled=false;$('noticeDone').textContent='休息好了';
  $('noticeTitle').textContent='好啦，慢慢回来';$('noticeMessage').textContent='谢谢你陪我歇一会儿。';
  noticeTimer=setTimeout(()=>finishHealth(false),2200);
 }
}
function healthReminder(kind){
 if(!healthCopy[kind]||currentHealth)return;
 if(!panel.hidden){pendingHealth=kind;return;}
 pendingHealth=null;currentHealth=kind;healthStage='entering';shownCount=null;
 clearTimeout(noticeTimer);noticeTimer=null;
 const copy=healthCopy[kind];$('noticeCard').dataset.kind=kind;$('noticeCard').dataset.stage='entering';
 $('noticeEyebrow').textContent='咕咕嘎嘎 · '+copy.label;$('noticeTitle').textContent=copy.title;$('noticeMessage').textContent=copy.message;
 $('noticeDone').textContent=copy.done;$('noticeDone').disabled=kind==='eyes';$('noticeLater').textContent='等一下';$('noticeLater').title=copy.later+'提醒';$('noticeLater').setAttribute('aria-label',copy.later+'提醒');
 $('restRing').hidden=kind!=='eyes';$('restCount').textContent='20';$('restFill').style.width='0%';
 $('noticeCharacter').setAttribute('aria-label',copy.label+'，点击角色回应');
 $('notice').hidden=false;$('noticeCharacter').hidden=false;$('noticeCard').hidden=true;$('notice').dataset.phase='entering';positionNotice();
 const film=ensureCinema();film?.start(kind,reducedMotion());
 const token=++healthAnimation,start=performance.now(),duration=reducedMotion()?0:2650;shotStarted=start;let lastRegion=0;
 function tick(now){
  if(token!==healthAnimation||!currentHealth||healthStage==='leaving')return;
  if(healthStage==='entering'){
   const t=duration?Math.min(1,(now-start)/duration):1;
   drawCinema(reducedMotion()?2.65:(now-start)/1000);
   if(t>=1){
    healthStage=kind==='eyes'?'resting':'ready';healthStarted=now;
    $('notice').dataset.phase='performing';$('noticeCard').dataset.stage=healthStage;$('noticeCard').hidden=false;positionNotice();
    if(!film)$('noticeMessage').textContent='提醒画面暂时无法显示，请先休息一下。';
    // Only an explicit “稍后” requests a short retry; unattended reminders use the normal interval.
    if(kind!=='eyes')noticeTimer=setTimeout(()=>finishHealth(false),6500);
   }
  }else updateHealth(now);
  if(now-lastRegion>40){regions();lastRegion=now;}requestAnimationFrame(tick);
 }
 requestAnimationFrame(tick);regions();
}
function dismissNotice(){
 ++healthAnimation;clearTimeout(noticeTimer);noticeTimer=null;
 currentHealth=null;healthStage='none';pendingHealth=null;shownCount=null;
 $('notice').hidden=true;$('noticeCard').hidden=true;$('noticeCharacter').hidden=true;cinema?.stop();
 regions();
}
async function finishHealth(snooze,{animate=true}={}){
 if(!currentHealth||healthStage==='leaving')return;
 const kind=currentHealth,token=++healthAnimation;healthStage='leaving';clearTimeout(noticeTimer);noticeTimer=null;
 $('notice').dataset.phase='leaving';$('noticeCard').hidden=true;regions();
 // Persist once at acknowledgement; repeated timer events cannot replay the reminder during exit.
 try{await api.finishReminder(kind,Boolean(snooze));}catch(error){console.error('保存提醒状态失败',error);}
 if(token!==healthAnimation||!currentHealth||healthStage!=='leaving')return;
 if(animate&&!reducedMotion()){
  const start=performance.now(),time=(start-shotStarted)/1000;
  await new Promise(resolve=>{
   function tick(now){
    if(token!==healthAnimation){resolve();return;}
    const t=Math.min(1,(now-start)/350);drawCinema(time+(now-start)/1000,'leaving',t);regions();
    if(t<1)requestAnimationFrame(tick);else resolve();
   }requestAnimationFrame(tick);
  });
 }
 if(token!==healthAnimation||currentHealth!==kind||healthStage!=='leaving')return;
 dismissNotice();
}
$('noticeDone').onclick=()=>{if(healthStage==='ready')finishHealth(false);};
$('noticeCharacter').onclick=()=>{if(healthStage==='ready')finishHealth(false);};
$('noticeLater').onclick=()=>finishHealth(true);
$('noticeClose').onclick=()=>finishHealth(false);
function applyReminderIntervals(values={}){
 for(const [kind,minutes] of Object.entries({water:60,walk:50,eyes:40,...values}))$(kind+'Interval').value=minutes;
}
$('reminderSettings').onsubmit=async e=>{
 e.preventDefault();if(!$('reminderSettings').reportValidity())return;
 const values=Object.fromEntries(['water','walk','eyes'].map(kind=>[kind,Number($(kind+'Interval').value)]));
 $('saveIntervals').disabled=true;$('intervalStatus').textContent='正在保存…';
 try{const result=await api.saveReminderIntervals(values);applyReminderIntervals(result.intervals);$('intervalStatus').textContent='已保存，重启后也会保留';}
 catch(error){console.error('保存提醒间隔失败',error);$('intervalStatus').textContent='保存失败，请重试';}
 finally{$('saveIntervals').disabled=false;regions();}
};

function applyReminderState(pausedUntil=0){
 const paused=pausedUntil>Date.now();$('pauseReminders').textContent=paused?'恢复提醒':'暂停 1 小时';$('pauseReminders').dataset.paused=String(paused);$('reminderStatus').textContent=paused?'● 已暂停 · 1 小时后自动恢复':'● 提醒进行中';
}
$('pauseReminders').onclick=async()=>{
 $('pauseReminders').disabled=true;
 try{const state=await api.setReminderPaused($('pauseReminders').dataset.paused!=='true');applyReminderState(state.pausedUntil);}
 catch(error){$('intervalStatus').textContent='操作失败，请重试';}
 finally{$('pauseReminders').disabled=false;regions();}
};
$('quitApp').onclick=()=>api.quit();
api.onEvent(e=>{
 if(e.kind==='reminder-state')applyReminderState(e.pausedUntil);
 if(e.kind==='reminder-settings-open')showSettings();
 if(e.kind==='reminder-settings'){applyReminderIntervals(e.intervals);if(e.changed.includes(pendingHealth))pendingHealth=null;}
 if(e.kind==='reminder')healthReminder(e.reminder);
 if(e.kind==='reminder-dismiss')dismissNotice();
 if(e.kind==='layout'){if(currentHealth){cinema?.resize();positionNotice();}regions();}
});
setInterval(()=>{if(pendingHealth&&!currentHealth)healthReminder(pendingHealth);},1000);
(async()=>{const data=await api.load();applyReminderIntervals(data.reminderIntervals);applyReminderState(data.pausedUntil);regions();})();
setInterval(regions,500);
window.onresize=()=>{if(currentHealth){cinema?.resize();positionNotice();}regions();};
document.addEventListener('keydown',e=>{
 if(e.key!=='Escape')return;
 if(currentHealth)finishHealth(false);
 else{panel.hidden=true;regions();}
});
