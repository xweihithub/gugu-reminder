import test from 'node:test';import assert from 'node:assert/strict';import clock from '../src/core/reminders.cjs';const {ReminderClock}=clock;
test('提醒间隔、完成和稍后重排',()=>{const c=new ReminderClock({},0);assert.equal(c.due(39*60000),null);assert.equal(c.due(40*60000),'eyes');c.finish('eyes',true,40*60000);assert.equal(c.due(44*60000),null);assert.equal(c.due(45*60000),'eyes');c.finish('eyes',false,45*60000);assert.equal(c.due(50*60000),'walk');c.finish('walk',false,50*60000);assert.equal(c.due(60*60000),'water');});
test('暂停与唤醒不会补发积压提醒',()=>{const c=new ReminderClock({},0);c.pause(0);assert.equal(c.due(3599999),null);assert.equal(c.due(3600000),null);c.reset(9000000);assert.equal(c.due(9000000),null);assert.deepEqual(new ReminderClock(c.snapshot(),9000000).snapshot(),c.snapshot());});

test('旧存档补入走动提醒，走动稍后十分钟，三种积压按顺序处理',()=>{
 const now=100*60000,c=new ReminderClock({next:{water:now+60000,eyes:now+120000}},now);
 assert.equal(c.next.walk,now+50*60000);
 c.finish('walk',true,now);assert.equal(c.next.walk,now+10*60000);
 const all=new ReminderClock({},0);assert.equal(all.due(70*60000),'eyes');
 all.finish('eyes',false,70*60000);assert.equal(all.due(70*60000),'walk');
 all.finish('walk',false,70*60000);assert.equal(all.due(70*60000),'water');
});

test('自定义间隔仅重排改动项目，完成后沿用设置，重启和唤醒仍保留',()=>{
 const c=new ReminderClock({},0),before=c.snapshot();
 assert.deepEqual(c.setIntervals({water:30,eyes:20},1000),['water','eyes']);
 assert.equal(c.next.walk,before.next.walk);assert.equal(c.next.water,1000+30*60000);
 c.finish('water',false,2000);assert.equal(c.next.water,2000+30*60000);
 c.finish('eyes',true,2000);assert.equal(c.next.eyes,2000+5*60000);
 const restored=new ReminderClock(JSON.parse(JSON.stringify(c.snapshot())),3000);
 assert.deepEqual(restored.snapshot(),c.snapshot());restored.reset(9000);
 assert.deepEqual(restored.next,{eyes:9000+20*60000,walk:9000+50*60000,water:9000+30*60000});
 const unchanged=restored.snapshot();assert.deepEqual(restored.setIntervals({water:30},10000),[]);assert.deepEqual(restored.snapshot(),unchanged);
});
test('暂停期间改间隔，从暂停结束后开始，不提前弹出',()=>{
 const c=new ReminderClock({},0);c.pause(0);c.setIntervals({eyes:1},60000);
 assert.equal(c.next.eyes,3600000+60000);assert.equal(c.due(3600000),null);assert.equal(c.due(3660000),'eyes');
});
test('间隔校验拒绝无效数值和未知类型，整批修改不部分生效',()=>{
 const c=new ReminderClock({},0),before=c.snapshot();
 for(const v of [0,-1,1.5,1441,NaN,Infinity,'30',null]){assert.throws(()=>c.setIntervals({water:30,eyes:v},100));assert.deepEqual(c.snapshot(),before);}
 assert.throws(()=>c.setIntervals({unknown:10}));assert.throws(()=>c.setIntervals(null));
 assert.deepEqual(c.setIntervals({eyes:1,water:1440},0),['eyes','water']);
});
test('损坏的自定义存档回到对应默认值，合法的设置保留',()=>{
 const c=new ReminderClock({intervals:{eyes:0,walk:25,water:'bad'},next:{eyes:'bad'},pausedUntil:'bad'},0);
 assert.deepEqual(c.intervals,{eyes:40,walk:25,water:60});assert.equal(c.next.eyes,40*60000);
});
