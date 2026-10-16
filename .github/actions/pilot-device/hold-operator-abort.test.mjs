import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {holdOperatorSession} from './hold-operator.mjs';

test('abort stops first-party queue instead of draining after terminal loss',async()=>{
 const root=await mkdtemp(join(tmpdir(),'pilot-hold-abort-'));
 const ctrl=new AbortController();let drains=0,clock=0;
 try{
  await writeFile(join(root,'session.json'),JSON.stringify({
   schema:1,runId:'8888',vmId:'01234567-89ab-cdef-0123-456789abcdef',
   generation:'devbox-checkpoint-v1-ci-1-1-20261014T225101Z-0123456789abcdef0123456789abcdef',
   deadlineMs:Date.now()+120000}));
  await assert.rejects(holdOperatorSession({controlDir:root,workspace:root,runId:'8888',
   now:()=>clock+=1000,maxMs:15000,signal:ctrl.signal,
   sleep:async()=>{ctrl.abort();},
   drain:async()=>{drains++;return {processed:0,verifiedFinish:false};},
   executor:async()=>({verified:false})
  }),/abort|terminated/i);
  assert.equal(drains,1);
 }finally{await rm(root,{recursive:true,force:true});}
});
