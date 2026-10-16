// Privileged Save/Finish remains first-party; external Desktop Commander uses a separate verified Windows SID.
import {spawn} from 'node:child_process';
import {readFile,writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {createPublicKey,publicEncrypt,constants} from 'node:crypto';

export function encryptPairing(value,key) {
 const raw=Buffer.from(value,'utf8');
 const lines=['PILOT_ENCRYPTED_PAIRING_BEGIN'];
 for(let pos=0,i=0;pos<raw.length;pos+=120,i++){
  const encrypted=publicEncrypt({key,padding:constants.RSA_PKCS1_OAEP_PADDING,oaepHash:'sha256'},raw.subarray(pos,pos+120));
  lines.push('PILOT_PAIR_'+i+'='+encrypted.toString('base64'));
 }
 lines.push('PILOT_ENCRYPTED_PAIRING_END');
 return lines.join('\n')+'\n';
}
export function pairingReady(output){return /device code received/i.test(output)&&/waiting for authorization/i.test(output);}
export function identityMatchesRun(session,runId){
 return session?.schema===1&&session?.runId===runId&&
  typeof session.root==='string'&&session.root.startsWith('E:/DevBox/Tools/WindowsStateProbe/probe-')&&
  Number.isSafeInteger(session.deadlineMs)&&session.deadlineMs>Date.now();
}
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const spawnTask=(exe,args,opts)=>spawn(exe,args,{windowsHide:true,...opts});
async function stopTree(pid){
 if(!Number.isSafeInteger(pid)||pid<=0)return;
 const child=spawnTask('taskkill.exe',['/PID',String(pid),'/T','/F'],{stdio:'ignore',timeout:10000});
 await new Promise(resolve=>{child.once('exit',resolve);child.once('error',resolve);});
}
// Losing an optional assistant terminal must not terminate the owner's RDP
// session or its independent first-party Save/Finish publisher.
export async function holdWithOptionalTerminal({hold,terminal,report}){
 const controller=new AbortController();
 const pairing=Promise.resolve().then(()=>terminal(controller.signal)).catch(()=>report());
 try{return await hold();}
 finally{controller.abort();await pairing;}
}
// Isolate potentially stalled network/artifact work in a killable first-party
// subprocess, so owner Finish never waits for an SDK upload retry to return.
export async function runPairingProcess(signal,{
 args=[fileURLToPath(import.meta.url),'--pair-only'],stop=stopTree
}={}){
 const child=spawnTask(process.execPath,args,{stdio:['ignore','inherit','inherit'],env:process.env});
 let cancel;
 try {
  await new Promise((resolve,reject)=>{
   cancel=()=>{stop(child.pid).then(resolve,reject);};
   child.once('error',reject);
   child.once('exit',code=>{
    if(signal.aborted||code===0)resolve();else reject(Error('Optional terminal subprocess failed'));
   });
   signal.addEventListener('abort',cancel,{once:true});
   if(signal.aborted)cancel();
  });
 } finally {signal.removeEventListener('abort',cancel);}
}
async function pairRestrictedTerminal({signal}){
 if(process.env.GITHUB_ACTIONS!=='true'||process.env.DEVBOX_ISOLATED_TEST!=='1'||
   process.env.GITHUB_EVENT_NAME!=='workflow_dispatch'||
   process.env.GITHUB_REF!=='refs/heads/pilot/windows-home-connection-20261015'||
   process.env.GITHUB_REPOSITORY!=='dougmcdonald87/dougs-box')throw Error('Pilot identity refused');
 const runId=process.env.GITHUB_RUN_ID;
 if(!/^[1-9]\d*$/.test(runId||''))throw Error('Invalid pilot run ID');
 const workspace=process.env.GITHUB_WORKSPACE, controlDir=process.env.WINDOWS_HOME_CONTROL_DIR;
 if(!workspace||!controlDir||!process.env.GH_TOKEN||!process.env.RESTIC_PASSWORD){
  throw Error('First-party publisher credentials or control directory unavailable');
 }
 const session=JSON.parse(await readFile(join(controlDir,'session.json'),'utf8'));
 if(!identityMatchesRun(session,runId))throw Error('Guest session does not match live runner');
 if(!process.env.PILOT_RSA_MODULUS)throw Error('Missing public pilot pairing key');
 const rsa=createPublicKey({key:{kty:'RSA',n:Buffer.from(process.env.PILOT_RSA_MODULUS,'base64').toString('base64url'),e:'AQAB'},format:'jwk'});
 const script=join(workspace,'scripts','windows-home-restricted-agent.ps1');
 const child=spawnTask('pwsh.exe',['-NoProfile','-NonInteractive','-File',script,
  '-ControlDir',controlDir,'-GuestRoot',session.root,'-WorkspaceRoot',workspace,'-LaunchAgent'],
  {cwd:workspace,stdio:['ignore','pipe','pipe'],env:process.env});
 let output='',exited=false;
 // Never forward raw device-code output to GitHub Actions logs.
 const capture=(bytes)=>{if(output.length<131072)output+=bytes.toString('utf8').slice(0,131072-output.length);};
 child.stdout.on('data',capture);child.stderr.on('data',capture);
 child.once('exit',()=>{exited=true;});child.once('error',()=>{exited=true;});
 try {
  let ready=false;
  const start=Date.now();
  while(Date.now()-start<300000){
   if(signal.aborted)return;
   if(/PILOT_RESTRICTED_IDENTITY_SENTINEL_DENIAL_OK=true/.test(output)&&pairingReady(output)){
    ready=true;break;
   }
   if(exited||output.length===131072)break;
   await delay(1000);
  }
  if(signal.aborted)return;
  // Even a denied native probe needs private diagnostic evidence. The payload
  // remains RSA-encrypted; plaintext is never forwarded to the Actions log.
  const payload=JSON.stringify({runId,ready:ready&&!exited,diagnostics:output});
  const root=process.env.RUNNER_TEMP;
  if(!root)throw Error('Temporary pairing root unavailable');
  const encrypted=join(root,'windows-home-pilot-pairing.encrypted.txt');
  await writeFile(encrypted,encryptPairing(payload,rsa),{mode:0o600,flag:'wx'});
  const {DefaultArtifactClient}=await import('@actions/artifact');
  const {id}=await new DefaultArtifactClient().uploadArtifact('windows-home-pilot-pairing-'+runId,[encrypted],root,{retentionDays:1});
  console.log('PILOT_ENCRYPTED_ARTIFACT_ID='+id);
  if(!ready||exited)throw Error('Restricted pairing agent did not pass identity/read-denial and device-code gates');
  console.log('PILOT_RESTRICTED_DEVICE_READY=true');
  while(!signal.aborted&&!exited)await delay(1000);
  if(exited&&!signal.aborted)throw Error('Restricted terminal exited');
 } finally {
  await stopTree(child.pid);
 }
}
export async function supervise(){
 if(process.env.GITHUB_ACTIONS!=='true'||process.env.DEVBOX_ISOLATED_TEST!=='1'||
   process.env.GITHUB_EVENT_NAME!=='workflow_dispatch'||
   process.env.GITHUB_REF!=='refs/heads/pilot/windows-home-connection-20261015'||
   process.env.GITHUB_REPOSITORY!=='dougmcdonald87/dougs-box')throw Error('Pilot identity refused');
 const {holdOperatorSession}=await import('./hold-operator.mjs');
 const outcome=await holdWithOptionalTerminal({
  hold:()=>holdOperatorSession({controlDir:process.env.WINDOWS_HOME_CONTROL_DIR,
   workspace:process.env.GITHUB_WORKSPACE,runId:process.env.GITHUB_RUN_ID}),
  terminal:signal=>runPairingProcess(signal),
  report:()=>console.log('PILOT_OPTIONAL_TERMINAL_UNAVAILABLE_OWNER_HOLD_CONTINUES')
 });
 console.log(outcome.completedFinish?'PILOT_VERIFIED_FINISH_HOLD_COMPLETE':'PILOT_HOLD_EXPIRED_WITHOUT_VERIFIED_FINISH');
 console.log('PILOT_OWNER_REQUESTS_PROCESSED='+outcome.processed);
}
if(process.argv[1]&&fileURLToPath(import.meta.url)===process.argv[1]){
 try{
  if(process.argv.includes('--pair-only'))await pairRestrictedTerminal({signal:new AbortController().signal});
  else await supervise();
 }catch(e){console.error('PILOT_RESTRICTED_PAIRING_FAILED='+e.name);process.exitCode=1;}
}
