import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,mkdir,writeFile,readFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {validateOperatorRequest} from './operator-requests.mjs';
import {drainOperatorRequests} from './operator-worker.mjs';
import {runOperatorPowerShell} from './operator-execution.mjs';
const id='c972fbc3-f1a9-46aa-b0b7-cd407c9ea775',now=Date.parse('2026-10-15T16:20:00Z');
const g='devbox-checkpoint-v1-ci-38647908553-1-20261014T225101Z-eb2366ef7dc34ea4aee45c30bbc721b6';
const session={vmId:'66b514d0-7246-493f-ade3-1f004cd12411',runId:'38750000000',generation:g,deadlineMs:now+100000};
const req={schema:1,vmId:session.vmId,runId:session.runId,generation:g,operation:'Save',operationId:id,createdUtc:new Date(now).toISOString()};
const generation='devbox-checkpoint-v1-ci-38750000000-1-20261015T162000Z-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
test('valid request, wrong VM, stale generation, forged commands, late request and replay',()=>{
 assert.equal(validateOperatorRequest(req,session,{nowMs:now}).ok,true);
 for(const patch of [{vmId:'00000000-0000-0000-0000-000000000001'},{generation:'old'},{operation:'Delete'},{runId:'999'},{extraneous:'secret'}]){
  assert.equal(validateOperatorRequest({...req,...patch},session,{nowMs:now}).ok,false);
 }
 assert.equal(validateOperatorRequest(req,session,{nowMs:session.deadlineMs}).ok,false);
 assert.equal(validateOperatorRequest(req,session,{nowMs:now,processed:new Set([id])}).ok,false);
 assert.equal(validateOperatorRequest(req,session,{nowMs:now,busy:true}).ok,false);
});
async function sandbox(fn){const root=await mkdtemp(join(tmpdir(),'windows-home-'));try{
 await mkdir(join(root,'requests'));await mkdir(join(root,'responses'));await fn(root);
}finally{await rm(root,{recursive:true,force:true});}}
const path=root=>join(root,'requests',`request-${id}.json`);
const response=root=>join(root,'responses',`response-${id}.json`);
test('worker verifies only after actual executor accepted-generation receipt',async()=>sandbox(async root=>{
 await writeFile(path(root),JSON.stringify(req));
 let calls=0;
 await drainOperatorRequests({root,session,nowMs:now,executor:async()=>{calls++;return {verified:true,generation};}});
 assert.equal(calls,1);
 const x=JSON.parse(await readFile(response(root),'utf8'));assert.equal(x.status,'verified');assert.equal(x.generation,generation);
}));
test('wrong VM and failed publisher never get verified receipt',async()=>sandbox(async root=>{
 await writeFile(path(root),JSON.stringify({...req,vmId:'00000000-0000-0000-0000-000000000001'}));
 let calls=0;await drainOperatorRequests({root,session,nowMs:now,executor:async()=>{calls++;}});
 assert.equal(calls,0);assert.equal(JSON.parse(await readFile(response(root))).verified,false);
}));
test('replay cannot execute twice after an executor failure',async()=>sandbox(async root=>{
 await writeFile(path(root),JSON.stringify(req));let calls=0;
 await drainOperatorRequests({root,session,nowMs:now,executor:async()=>{calls++;throw Error('failure')}});
 await writeFile(path(root),JSON.stringify(req));
 await drainOperatorRequests({root,session,nowMs:now,executor:async()=>{calls++;return {verified:true,generation}}});
 assert.equal(calls,1);assert.equal(JSON.parse(await readFile(response(root))).status,'failed');
}));
test('operator executor invokes PowerShell without a command shell or credentials',async()=>{
 const calls=[];
 const payload={verified:true,operationId:id,vmId:session.vmId,generation};
 const result=await runOperatorPowerShell(req,{controlDir:'C:\\ProgramData\\WindowsHomePilot\\38750000000',workspace:'C:\\a\\repo'},{
  spawnCommand:async(exe,args,opts)=>{calls.push({exe,args,opts});return 0;},
  readResult:async()=>JSON.stringify(payload)
 });
 assert.equal(result.verified,true);assert.equal(calls[0].opts.shell,false);
 assert.equal(calls[0].exe,'pwsh.exe');
 assert.doesNotMatch(calls[0].args.join(' '),/GH_TOKEN|RESTIC_PASSWORD/);
});
test('failed publisher receipt identifies exit code without leaking exception text',async()=>sandbox(async root=>{
 await writeFile(path(root),JSON.stringify(req));
 await drainOperatorRequests({root,session,nowMs:now,executor:async()=>{
  const error=Error('synthetic-private-value');error.operatorExitCode=17;throw error;
 }});
 const text=await readFile(response(root),'utf8');
 assert.equal(JSON.parse(text).exitCode,17);
 assert.doesNotMatch(text,/synthetic-private-value/);
}));
