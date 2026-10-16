import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,readFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import * as execution from './operator-execution.mjs';

test('failed child preserves private diagnostics without printing its output',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'operator-diagnostics-'));
 try {
  const logPath=join(dir,'private.log');
  assert.equal(typeof execution.executeOperatorProcess,'function');
  const code=await execution.executeOperatorProcess(process.execPath,
   ['-e',"process.stdout.write('stage-export');process.stderr.write('synthetic-private-value');process.exitCode=17"],
   {cwd:dir,logPath});
  assert.equal(code,17);
  const text=await readFile(logPath,'utf8');
  assert.match(text,/stage-export/);
  assert.match(text,/synthetic-private-value/);
 } finally {await rm(dir,{recursive:true,force:true});}
});

test('executor exposes only bounded exit code and scoped diagnostic filename',async()=>{
 const request={operation:'Save',operationId:'c972fbc3-f1a9-46aa-b0b7-cd407c9ea775',runId:'38924343812'};
 await assert.rejects(execution.runOperatorPowerShell(request,{controlDir:'/private',workspace:'/repo'},
  {spawnCommand:async(_exe,_args,opts)=>{
   assert.equal(opts.logPath,join('/private','responses','.operator-'+request.operationId+'.log'));
   return 17;
  }}),error=>error.message==='operator script failed (exit 17)'&&error.operatorExitCode===17);
});
