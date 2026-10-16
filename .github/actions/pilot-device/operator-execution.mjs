import {spawn} from 'node:child_process';
import {join} from 'node:path';
import {readFile,open} from 'node:fs/promises';
// The parent directory is owner/SYSTEM-only. Never forward raw publisher output
// to Actions logs or owner receipts: it may contain sensitive transport details.
export async function executeOperatorProcess(exe,args,{logPath,...opts}){
 const log=await open(logPath,'wx',0o600);
 try {
  return await new Promise((resolve,reject)=>{
   const child=spawn(exe,args,{...opts,windowsHide:true,stdio:['ignore',log.fd,log.fd]});
   child.once('error',reject);
   child.once('close',resolve);
  });
 } finally {await log.close();}
}
export async function runOperatorPowerShell(request,{controlDir,workspace},{spawnCommand:run=executeOperatorProcess,readResult=path=>readFile(path,'utf8')}={}){
 const output=join(controlDir,'responses',`.internal-${request.operationId}.json`);
 const script=join(workspace,'scripts','windows-state-operator.ps1');
 const args=['-NoProfile','-NonInteractive','-File',script,'-Operation',request.operation,'-OperationId',request.operationId,'-ExpectedRunId',request.runId,'-ControlDir',controlDir,'-OutputPath',output];
 const logPath=join(controlDir,'responses',`.operator-${request.operationId}.log`);
 const code=await run('pwsh.exe',args,{cwd:workspace,shell:false,env:process.env,logPath});
 if(code!==0){
  const safeCode=Number.isInteger(code)&&code>=0&&code<=2147483647?code:null;
  const error=Error(`operator script failed (exit ${safeCode??'unknown'})`);
  error.operatorExitCode=safeCode;
  throw error;
 }
 const value=JSON.parse(await readResult(output));
 if(value.operationId!==request.operationId||value.vmId!==request.vmId||value.verified!==true||typeof value.generation!=='string')throw Error('operator response verification mismatch');
 return {verified:true,generation:value.generation};
}
