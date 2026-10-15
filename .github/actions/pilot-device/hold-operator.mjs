// First-party, privileged Save/Finish hold. NO third-party remote agent here.
import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {drainOperatorRequests} from './operator-worker.mjs';
import {runOperatorPowerShell} from './operator-execution.mjs';

const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
const generationPattern=/^devbox-checkpoint-v1-ci-[1-9]\d*-[1-9]\d*-[0-9]{8}T[0-9]{6}Z-[0-9a-f]{32}$/;
const vmPattern=/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/;

export async function holdOperatorSession({controlDir,workspace,runId,
  now=Date.now,sleep=delay,drain=drainOperatorRequests,executor=runOperatorPowerShell,maxMs=300*60*1000}){
 if(!controlDir||!workspace||!runId||!Number.isFinite(maxMs)||maxMs<=0||maxMs>300*60*1000){
  throw Error('Invalid first-party hold parameters');
 }
 const session=JSON.parse(await readFile(join(controlDir,'session.json'),'utf8'));
 if(session.schema!==1||session.runId!==runId||!/^[1-9]\d*$/.test(runId)||
   typeof session.vmId!=='string'||!vmPattern.test(session.vmId)||
   typeof session.generation!=='string'||!generationPattern.test(session.generation)||
   !Number.isSafeInteger(session.deadlineMs)||session.deadlineMs<=Date.now()){
  throw Error('Refused forged, expired or mismatched operator session');
 }
 const stopAt=now()+maxMs;
 let processed=0;
 while(now()<stopAt){
  const outcome=await drain({root:controlDir,session,
   executor:request=>executor(request,{controlDir,workspace})});
  processed+=outcome.processed;
  if(outcome.verifiedFinish===true)return {completedFinish:true,processed};
  await sleep(10000);
 }
 return {completedFinish:false,reason:'hold-expired',processed};
}

if(process.argv[1]&&fileURLToPath(import.meta.url)===process.argv[1]){
 try{
  const out=await holdOperatorSession({controlDir:process.env.WINDOWS_HOME_CONTROL_DIR,
   workspace:process.env.GITHUB_WORKSPACE,runId:process.env.GITHUB_RUN_ID});
  console.log(out.completedFinish?'PILOT_VERIFIED_FINISH_HOLD_COMPLETE':'PILOT_HOLD_EXPIRED_WITHOUT_VERIFIED_FINISH');
  console.log(`PILOT_OWNER_REQUESTS_PROCESSED=${out.processed}`);
 }catch(error){
  console.error('PILOT_FIRST_PARTY_HOLD_FAILED='+error.name);
  process.exitCode=1;
 }
}
