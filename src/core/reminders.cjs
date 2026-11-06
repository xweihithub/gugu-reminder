const defaults={eyes:40,walk:50,water:60};
const valid=v=>Number.isInteger(v)&&v>=1&&v<=1440;
class ReminderClock {
 constructor(saved={},now=Date.now()){
  this.next={};this.intervals={};this.pausedUntil=Number.isFinite(saved?.pausedUntil)?saved.pausedUntil:0;
  for(const k of Object.keys(defaults)){
   this.intervals[k]=valid(saved?.intervals?.[k])?saved.intervals[k]:defaults[k];
   const next=saved?.next?.[k];this.next[k]=Number.isFinite(next)&&next>now?next:Math.max(now,this.pausedUntil)+this.intervals[k]*60000;
  }
 }
 due(now=Date.now()){if(now<this.pausedUntil)return null;const k=Object.keys(defaults).sort((a,b)=>this.next[a]-this.next[b])[0];return this.next[k]<=now?k:null;}
 finish(k,snooze=false,now=Date.now()){if(!Object.hasOwn(defaults,k))throw Error('未知提醒类型');this.next[k]=now+(snooze?(k==='eyes'?5:10):this.intervals[k])*60000;}
 setIntervals(values,now=Date.now()){
  if(!values||typeof values!=='object'||Array.isArray(values))throw Error('请提供提醒间隔');
  for(const [k,v] of Object.entries(values))if(!Object.hasOwn(defaults,k)||!valid(v))throw Error('提醒间隔需为1–1440分钟的整数');
  const changed=[];
  for(const [k,v] of Object.entries(values))if(this.intervals[k]!==v){this.intervals[k]=v;this.next[k]=Math.max(now,this.pausedUntil)+v*60000;changed.push(k);}
  return changed;
 }
 pause(now=Date.now()){this.pausedUntil=now+3600000;this.reset(this.pausedUntil);this.pausedUntil=now+3600000;}
 reset(now=Date.now()){this.pausedUntil=0;for(const k of Object.keys(defaults))this.next[k]=now+this.intervals[k]*60000;}
 snapshot(){return {next:{...this.next},pausedUntil:this.pausedUntil,intervals:{...this.intervals}};}
}
module.exports={ReminderClock};
