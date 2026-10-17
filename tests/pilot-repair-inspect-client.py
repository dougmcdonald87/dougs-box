"""Read-only inspection of one pinned, live retained Windows pilot; encrypted result."""
import base64,json,os,re,subprocess,time,urllib.request
from pathlib import Path
import winrm
from pilot_repair_metadata import fetch_metadata
from cryptography.hazmat.primitives.asymmetric import rsa,padding
from cryptography.hazmat.primitives import hashes
def make_inspection_command(run,sha,source,encoded=True):
    import gzip
    if not re.fullmatch('[1-9][0-9]*',run) or not re.fullmatch('[0-9a-f]{40}',sha):raise ValueError('Pinned inspection target required')
    source=source.replace('\r\n','\n').replace('__TARGET_RUN__',run).replace('__TARGET_SHA__',sha)
    packed=base64.b64encode(gzip.compress(source.encode(),mtime=0)).decode()
    command=f'''$ErrorActionPreference='Stop'
$b=[Convert]::FromBase64String('{packed}')
$m=New-Object IO.MemoryStream(,$b)
$g=New-Object IO.Compression.GZipStream($m,[IO.Compression.CompressionMode]::Decompress)
$r=New-Object IO.StreamReader($g,[Text.Encoding]::UTF8)
try{{&([scriptblock]::Create($r.ReadToEnd()))}}finally{{$r.Dispose();$g.Dispose();$m.Dispose()}}
'''
    size=len(base64.b64encode(command.encode('utf-16-le'))) if encoded else len(command)
    if size+100>8000:raise ValueError('Inspection command exceeds native budget')
    return command

def run_private_script(session,command,password):
    """Only the encrypted transient shell environment carries the owner password."""
    import types
    payload=command.encode('utf-8')
    if len(payload)>65536:raise ValueError('Private stdin payload exceeds bounded envelope')
    loader="$ErrorActionPreference='Stop';[Console]::InputEncoding=[Text.UTF8Encoding]::new($false);[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false);$s=[Console]::In.ReadToEnd();&([scriptblock]::Create($s))"
    encoded=base64.b64encode(loader.encode('utf-16-le')).decode()
    shell=session.protocol.open_shell(env_vars={'PILOT_GUEST_OWNER_PASSWORD':password},codepage=65001)
    operation=None
    try:
        operation=session.protocol.run_command(shell,'powershell.exe',['-NoLogo','-NoProfile','-NonInteractive','-EncodedCommand',encoded],skip_cmd_shell=True,console_mode_stdin=False)
        session.protocol.send_command_input(shell,operation,payload,end=True)
        out,err,status=session.protocol.get_command_output(shell,operation)
        return types.SimpleNamespace(std_out=out,std_err=err,status_code=status)
    finally:
        try:
            if operation is not None:session.protocol.cleanup_command(shell,operation)
        finally:session.protocol.close_shell(shell)

run=os.environ.get('PILOT_TARGET_RUN_ID','');sha=os.environ.get('PILOT_TARGET_SHA','')
if not re.fullmatch('[1-9][0-9]*',run) or not re.fullmatch('[0-9a-f]{40}',sha):raise SystemExit('Pinned pilot target required')
req=urllib.request.Request('https://api.github.com/repos/dougmcdonald87/dougs-box/actions/runs/'+run,headers={'Authorization':'Bearer '+os.environ['GH_TOKEN'],'Accept':'application/vnd.github+json'})
with urllib.request.urlopen(req,timeout=20) as response:target=json.load(response)
if target['head_sha']!=sha or target['head_branch']!='pilot/windows-home-connection-20261015' or target['event']!='workflow_dispatch' or target['path']!='.github/workflows/windows-state-probe-validate.yml' or target['status']!='in_progress':raise SystemExit('Target is not the exact live retained pilot')
mode=os.environ.get('PILOT_INSPECTION_MODE','disks')
if mode not in ('disks','guest-evidence'):raise SystemExit('Unknown bounded inspection mode')
metadata=fetch_metadata(run,sha,os.environ['GH_TOKEN'])
if metadata is None:raise SystemExit('Retained host bootstrap metadata unavailable')
source='scripts/windows-home-guest-evidence.ps1' if mode=='guest-evidence' else 'scripts/windows-home-repair-inspect.ps1'
script=make_inspection_command(run,sha,Path(source).read_text(),encoded=mode=='disks')
end=time.monotonic()+1200;result=None
while time.monotonic()<end:
    peers=json.loads(subprocess.check_output(['tailscale','status','--json'])).get('Peer',{}).values()
    peers=[p for p in peers if p.get('HostName')=='windows-home-pilot-'+run or p.get('DNSName','').split('.')[0]=='windows-home-pilot-'+run]
    if len(peers)!=1:time.sleep(10);continue
    ips=[ip for ip in peers[0].get('TailscaleIPs',[]) if re.fullmatch(r'100\.(?:6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]{1,3}\.[0-9]{1,3}',ip)]
    if len(ips)!=1 or ips[0]!=metadata['ip']:raise SystemExit('Exact pilot private address unavailable')
    for account in [metadata['account']]:
        try:
            session=winrm.Session('http://'+ips[0]+':5985/wsman',auth=(account,os.environ['PILOT_OWNER_PASSWORD']),transport='ntlm',message_encryption='always',operation_timeout_sec=30,read_timeout_sec=40)
            native=run_private_script(session,script,os.environ['PILOT_OWNER_PASSWORD']) if mode=='guest-evidence' else session.run_ps(script)
            if native.status_code!=0:
                result={'runId':run,'kind':'repair-inspection','exitCode':native.status_code,'stderr':native.std_err.decode(errors='replace')};break
            data=json.loads(native.std_out.decode('utf-8-sig'))
            if data['runId']!=run:raise ValueError('target mismatch')
            if data['phase'] in ('inspected','guest-evidence'):result={'runId':run,'kind':'repair-inspection','data':data};break
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
