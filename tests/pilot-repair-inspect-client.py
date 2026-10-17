"""Read-only inspection of one pinned, live retained Windows pilot; encrypted result."""
import base64,json,os,re,subprocess,time,urllib.request
from pathlib import Path
import winrm
from cryptography.hazmat.primitives.asymmetric import rsa,padding
from cryptography.hazmat.primitives import hashes
run=os.environ.get('PILOT_TARGET_RUN_ID','');sha=os.environ.get('PILOT_TARGET_SHA','')
if not re.fullmatch('[1-9][0-9]*',run) or not re.fullmatch('[0-9a-f]{40}',sha):raise SystemExit('Pinned pilot target required')
req=urllib.request.Request('https://api.github.com/repos/dougmcdonald87/dougs-box/actions/runs/'+run,headers={'Authorization':'Bearer '+os.environ['GH_TOKEN'],'Accept':'application/vnd.github+json'})
with urllib.request.urlopen(req,timeout=20) as response:target=json.load(response)
if target['head_sha']!=sha or target['head_branch']!='pilot/windows-home-connection-20261015' or target['event']!='workflow_dispatch' or target['path']!='.github/workflows/windows-state-probe-validate.yml' or target['status']!='in_progress':raise SystemExit('Target is not the exact live retained pilot')
script=Path('scripts/windows-home-repair-inspect.ps1').read_text().replace('__TARGET_RUN__',run).replace('__TARGET_SHA__',sha)
end=time.monotonic()+1200;result=None
while time.monotonic()<end:
    peers=json.loads(subprocess.check_output(['tailscale','status','--json'])).get('Peer',{}).values()
    peers=[p for p in peers if p.get('HostName')=='windows-home-pilot-'+run or p.get('DNSName','').split('.')[0]=='windows-home-pilot-'+run]
    if len(peers)!=1:time.sleep(10);continue
    ips=[ip for ip in peers[0].get('TailscaleIPs',[]) if re.fullmatch(r'100\.(?:6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]{1,3}\.[0-9]{1,3}',ip)]
    if len(ips)!=1:raise SystemExit('Exact pilot private address unavailable')
    for account in ['runneradmin','devbox']:
        try:
            session=winrm.Session('http://'+ips[0]+':5985/wsman',auth=(account,os.environ['PILOT_OWNER_PASSWORD']),transport='ntlm',message_encryption='always',operation_timeout_sec=30,read_timeout_sec=40)
            native=session.run_ps(script)
            if native.status_code!=0:
                result={'runId':run,'kind':'repair-inspection','exitCode':native.status_code,'stderr':native.std_err.decode(errors='replace')};break
            data=json.loads(native.std_out.decode('utf-8-sig'))
            if data['runId']!=run:raise ValueError('target mismatch')
            if data['phase']=='inspected':result={'runId':run,'kind':'repair-inspection','data':data};break
        except Exception:continue
    if result is not None:break
    time.sleep(15)
if result is None:raise SystemExit('Retained guest inspection did not become available before bounded timeout')
public=rsa.RSAPublicNumbers(65537,int.from_bytes(base64.b64decode(os.environ['PILOT_RSA_MODULUS']),'big')).public_key()
raw=json.dumps(result).encode();print('LIVE_RESULT_BEGIN')
for index,offset in enumerate(range(0,len(raw),120)):
    cipher=public.encrypt(raw[offset:offset+120],padding.OAEP(mgf=padding.MGF1(hashes.SHA256()),algorithm=hashes.SHA256(),label=None))
    print('LIVE_RESULT_'+str(index)+'='+base64.b64encode(cipher).decode())
print('LIVE_RESULT_END')
