import test from 'node:test';
import assert from 'node:assert/strict';
import * as supervisor from './supervise-restricted.mjs';

test('terminal pairing failure leaves owner Save Finish session alive',async()=>{
 assert.equal(typeof supervisor.holdWithOptionalTerminal,'function');
 let release;
 const owner=new Promise(resolve=>{release=resolve;});
 let failures=0,finished=false;
 const running=supervisor.holdWithOptionalTerminal({
  hold:()=>owner,terminal:async()=>{throw Error('pairing unavailable');},
  report:()=>{failures++;}
 }).then(value=>{finished=true;return value;});
 await new Promise(resolve=>setImmediate(resolve));
 assert.equal(failures,1);assert.equal(finished,false);
 release({completedFinish:true,processed:2});
 assert.equal((await running).completedFinish,true);
});

test('verified owner Finish stops the optional terminal',async()=>{
 assert.equal(typeof supervisor.holdWithOptionalTerminal,'function');
 let stopped=false;
 const result=await supervisor.holdWithOptionalTerminal({
  hold:async()=>({completedFinish:true}),
  terminal:signal=>new Promise(resolve=>{
   if(signal.aborted){stopped=true;resolve();return;}
   signal.addEventListener('abort',()=>{stopped=true;resolve();},{once:true});
  }),report:()=>{}
 });
 assert.equal(result.completedFinish,true);assert.equal(stopped,true);
});
