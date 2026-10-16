const idPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const requestName = /^request-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\.json$/;
const genPattern = /^devbox-checkpoint-v1-ci-[1-9]\d*-[1-9]\d*-[0-9]{8}T[0-9]{6}Z-[a-f0-9]{32}$/;
const keys=['schema','runId','vmId','generation','operation','operationId','createdUtc'];
export function validateOperatorRequest(value,session,opts={}) {
 const reject=reason=>({ok:false,reason});
 if(!value||typeof value!=='object'||Array.isArray(value))return reject('malformed');
 if(Object.keys(value).sort().join(',')!==[...keys].sort().join(','))return reject('request-schema');
 if(value.schema!==1||typeof value.runId!=='string'|| !/^[1-9]\d*$/.test(value.runId))return reject('request-schema');
 if(typeof value.vmId!=='string'||!idPattern.test(value.vmId)||value.vmId!==session.vmId.toLowerCase())return reject('foreign-vm');
 if(typeof value.generation!=='string'||!genPattern.test(value.generation)||value.generation!==session.generation)return reject('generation');
 if(value.runId!==session.runId)return reject('foreign-run');
 if(!['Save','Finish'].includes(value.operation)||typeof value.operationId!=='string'||!idPattern.test(value.operationId))return reject('operation');
 if(opts.processed?.has(value.operationId))return reject('replay');
 if(opts.busy)return reject('concurrent-operation');
 if(typeof value.createdUtc!=='string'|| !/^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,3})?Z$/.test(value.createdUtc))return reject('timestamp');
 const stamp=Date.parse(value.createdUtc),nowMs=opts.nowMs??Date.now();
 if(!Number.isFinite(stamp)||stamp>nowMs+5000||stamp<nowMs-600000)return reject('stale-or-future');
 if(!Number.isFinite(session.deadlineMs)||nowMs>=session.deadlineMs)return reject('insufficient-time');
 return {ok:true};
}
export const nextRequest=names=>names.filter(x=>typeof x==='string'&&requestName.test(x)).sort();
export function formatOperatorReceipt(request,status,extra={}){
 if(!['received','running','verified','failed'].includes(status))throw new Error('invalid receipt state');
 return {schema:1,operationId:request.operationId,operation:request.operation,status,verified:status==='verified',...extra};
}
