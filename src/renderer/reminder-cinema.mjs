// 播放已确认角色的真实透明视频；这里不生成角色或动作。
class ReminderCinema {
 constructor(surface){
  this.surface=surface;this.video=surface.querySelector('video');this.still=surface.querySelector('img');
  this.active=false;this.kind='water';this.clip='water';this.reduced=false;this.run=0;
  this.video.addEventListener('error',()=>{
   if(!this.active)return;
   console.error('透明提醒视频无法播放',this.video.error);
   this.video.hidden=true;this.still.hidden=false;
  });
 }
 resize(){}
 start(kind,reduced=false){
  this.kind=kind;this.reduced=reduced;this.active=true;const run=++this.run;
  this.surface.hidden=false;this.surface.style.opacity='1';
  this.video.pause();
  const clip=['walk','eyes'].includes(kind)?kind:'water';
  if(this.clip!==clip){this.clip=clip;this.video.src=`assets/gugugaga-${clip}-alpha.webm`;this.still.src=`assets/gugugaga-${clip}-rest.png`;}
  this.video.currentTime=0;this.video.hidden=reduced;this.still.hidden=!reduced;
  if(!reduced)this.video.play().catch(error=>{
   if(run!==this.run||!this.active)return;
   console.error('透明提醒视频播放失败',error);this.video.hidden=true;this.still.hidden=false;
  });
 }
 stop(){
  ++this.run;this.active=false;this.video.pause();this.video.currentTime=0;this.surface.hidden=true;
 }
 render(time,phase='entering',exit=0){
  if(!this.active)return;
  // 三种提醒分别播放完整的透明短片，结束后自然停在末帧。
  if(phase==='leaving')this.video.pause();
  this.surface.style.opacity=String(1-Math.max(0,Math.min(1,exit)));
 }
 hitRect(){
  const r=this.surface.getBoundingClientRect();
  return{x:r.x+r.width*.08,y:r.y+r.height*.03,width:r.width*.84,height:r.height*.94};
 }
}
window.PawCinema={create:surface=>new ReminderCinema(surface),entry:2.65};
