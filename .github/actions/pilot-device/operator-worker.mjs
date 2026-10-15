import {readdir,lstat,readFile,rename,writeFile,access,unlink} from 'node:fs/promises';
import {join} from 'node:path';
import {randomUUID} from 'node:crypto';
import {nextRequest,validateOperatorRequest,formatOperatorReceipt} from './operator-requests.mjs';
const receiptFile=(root,id)=>join(root,'responses',`response-${id}.json`);
async function exists(path){try{await access(path);return true;}catch{return false;}}
async function saveReceipt(root,req,status,extra={}){
 const dest=receiptFile(root,req.operationId),temp=join(root,'responses',`.receipt-${randomUUID()}.tmp`);
 await writeFile(temp,JSON.stringify(formatOperatorReceipt(req,status,extra))+'\n',{encoding:'utf8',flag:'wx'});
 await rename(temp,dest);
}
export async function drainOperatorRequests({root,session,executor,nowMs=undefined}){
 if(typeof root!=='string'||typeof executor!=='function')throw new Error('worker configuration');
 const claimedAtMs=nowMs??Date.now();
 const names=nextRequest(await readdir(join(root,'requests')));
 let verifiedFinish=false,processed=0;
 const queue=[];
 // Claim files before ordering, so their request data cannot change mid-publish.
 for(const name of names){
  const original=join(root,'requests',name),working=original+'.working';
  let info;
  try{info=await lstat(original);}catch{continue;}
  if(!info.isFile()||info.isSymbolicLink()||info.size>4096)continue;
  try{await rename(original,working);}catch{continue;}
  const opId=name.slice('request-'.length,-'.json'.length);
  let req;
  try{req=JSON.parse(await readFile(working,'utf8'));if(req.operationId!==opId)throw Error('id');}
  catch{req={operationId:opId,operation:'Invalid'};}
  const stamp=typeof req.createdUtc==='string'?Date.parse(req.createdUtc):NaN;
  queue.push({name,working,opId,req,stamp:Number.isFinite(stamp)?stamp:Infinity});
 }
 // Explicit owner submit time takes precedence over arbitrary UUID filename order.
 queue.sort((a,b)=>a.stamp-b.stamp||a.name.localeCompare(b.name));
 for(const {name,working,opId,req} of queue){
  if(await exists(receiptFile(root,opId))){await unlink(working);continue;}
  if(verifiedFinish){await saveReceipt(root,req,'failed',{reason:'session-finished'});await unlink(working);processed++;continue;}
  const valid=validateOperatorRequest(req,session,{nowMs:claimedAtMs});
  if(!valid.ok){await saveReceipt(root,req,'failed',{reason:valid.reason});await unlink(working);processed++;continue;}
  await saveReceipt(root,req,'received');
  try{
   const result=await executor(req);
   if(result?.verified===true&&typeof result.generation==='string'&&/^devbox-checkpoint-v1-ci-\d+-\d+-\d{8}T\d{6}Z-[0-9a-f]{32}$/.test(result.generation)){
    await saveReceipt(root,req,'verified',{generation:result.generation});
    if(req.operation==='Finish')verifiedFinish=true;
   }else await saveReceipt(root,req,'failed',{reason:'publisher-not-verified'});
  }catch{await saveReceipt(root,req,'failed',{reason:'executor-failed'});}
  finally{await unlink(working);processed++;}
 }
 return {processed,verifiedFinish};
}
