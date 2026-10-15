import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,mkdir,writeFile,readFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {drainOperatorRequests} from './operator-worker.mjs';
const now=Date.parse('2026-10-15T16:20:00Z');
const gen='devbox-checkpoint-v1-ci-38647908553-1-20261014T225101Z-eb2366ef7dc34ea4aee45c30bbc721b6';
const latest='devbox-checkpoint-v1-ci-38750000000-1-20261015T162000Z-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
test('queued Save then Finish executes in owner order',async()=>{
 const root=await mkdtemp(join(tmpdir(),'pilot-test-'));
 try{
 await mkdir(join(root,'requests'));await mkdir(join(root,'responses'));
 const vmId='66b514d0-7246-493f-ade3-1f004cd12411';
 const session={vmId,runId:'38750000000',generation:gen,deadlineMs:now+100000};
 for(const [operation,id,time] of [['Save','c972fbc3-f1a9-46aa-b0b7-cd407c9ea77f',now-1000],['Finish','c972fbc3-f1a9-46aa-b0b7-cd407c9ea770',now]]){
   const req={schema:1,runId:session.runId,vmId,generation:gen,operation,operationId:id,createdUtc:new Date(time).toISOString()};
   await writeFile(join(root,'requests','request-'+id+'.json'),JSON.stringify(req));
 }
 const executed=[];
 const result=await drainOperatorRequests({root,session,nowMs:now,executor:async req=>{executed.push(req.operation);return {verified:true,generation:latest};}});
 assert.deepEqual(executed,['Save','Finish']);
 assert.equal(result.verifiedFinish,true);
 }finally{await rm(root,{recursive:true,force:true});}
});
