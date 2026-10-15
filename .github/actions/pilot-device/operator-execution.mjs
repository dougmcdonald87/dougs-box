import {spawn} from 'node:child_process';
import {join} from 'node:path';
import {readFile} from 'node:fs/promises';
const spawnCommand=(exe,args,opts)=>new Promise((resolve,reject)=>{
 const child=spawn(exe,args,{...opts,windowsHide:true,stdio:'ignore'});
 child.once('error',reject);
 child.once('close',resolve);
});
export async function runOperatorPowerShell(request,{controlDir,workspace},{spawnCommand:run=spawnCommand,readResult=path=>readFile(path,'utf8')}={}){
 const output=join(controlDir,'responses',`.internal-${request.operationId}.json`);
 const script=join(workspace,'scripts','windows-state-operator.ps1');
 const args=['-NoProfile','-NonInteractive','-File',script,'-Operation',request.operation,'-OperationId',request.operationId,'-ExpectedRunId',request.runId,'-ControlDir',controlDir,'-OutputPath',output];
 const code=await run('pwsh.exe',args,{cwd:workspace,shell:false,env:process.env});
 if(code!==0)throw Error('operator script failed');
 const value=JSON.parse(await readResult(output));
 if(value.operationId!==request.operationId||value.vmId!==request.vmId||value.verified!==true||typeof value.generation!=='string')throw Error('operator response verification mismatch');
 return {verified:true,generation:value.generation};
}
