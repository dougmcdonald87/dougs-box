import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,mkdir,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {holdOperatorSession} from './hold-operator.mjs';
const gen='devbox-checkpoint-v1-ci-38647908553-1-20261014T225101Z-eb2366ef7dc34ea4aee45c30bbc721b6';
async function setup(fn){const root=await mkdtemp(join(tmpdir(),'pilot-hold-'));try{
 await mkdir(join(root,'requests'));await mkdir(join(root,'responses'));
 await writeFile(join(root,'session.json'),JSON.stringify({schema:1,runId:'38999999999',vmId:'66b514d0-7246-493f-ade3-1f004cd12411',generation:gen,deadlineMs:Date.now()+3600000}));
 await fn(root);
}finally{await rm(root,{recursive:true,force:true});}}
test('first-party hold ends on verified Finish without starting external device agent',async()=>setup(async root=>{
 let ticks=0;const seen=[];
 const result=await holdOperatorSession({controlDir:root,workspace:'C:/repo',runId:'38999999999',
  now:()=>ticks*1000, sleep:async()=>{ticks++;},maxMs:10000,
  drain:async args=>{seen.push(args);return {verifiedFinish:seen.length===2,processed:1};},
  executor:async()=>({verified:false})});
 assert.equal(result.completedFinish,true);
 assert.equal(seen.length,2);
 assert.equal(seen[0].root,root);
 assert.equal(typeof seen[0].executor,'function');
}));
test('hold ending without Finish never claims Finish was verified',async()=>setup(async root=>{
 let ticks=0;
 const result=await holdOperatorSession({controlDir:root,workspace:'C:/repo',runId:'38999999999',
  now:()=>ticks*1000,sleep:async()=>{ticks+=5;},maxMs:10000,
  drain:async()=>({verifiedFinish:false,processed:0}),executor:async()=>({verified:false})});
 assert.equal(result.completedFinish,false);
 assert.equal(result.reason,'hold-expired');
}));
test('hold rejects wrong runner identity before processing any commands',async()=>setup(async root=>{
 let calls=0;
 await assert.rejects(holdOperatorSession({controlDir:root,workspace:'C:/repo',runId:'wrong',drain:async()=>{calls++;}}));
 assert.equal(calls,0);
}));
