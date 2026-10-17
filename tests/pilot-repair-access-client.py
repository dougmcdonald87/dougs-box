"""Independent pilot-only WinRM readiness check. No guest restoration or publisher."""
import json,os,re,subprocess,time,base64
import winrm
run=os.environ.get('GITHUB_RUN_ID','');sha=os.environ.get('GITHUB_SHA','');password=os.environ.get('PILOT_OWNER_PASSWORD','')
if not re.fullmatch(r'[1-9][0-9]*',run) or not re.fullmatch('[0-9a-f]{40}',sha) or not password:raise SystemExit('Pilot readiness context unavailable')
target='windows-home-pilot-'+run
end=time.monotonic()+480
verified=False;last_failure={"class":"not-connected"}
while time.monotonic()<end and not verified:
    state=json.loads(subprocess.check_output(['tailscale','status','--json']))
    peers=[p for p in state.get('Peer',{}).values() if p.get('HostName')==target or p.get('DNSName','').split('.')[0]==target]
    if len(peers)!=1:time.sleep(5);continue
    ips=[ip for ip in peers[0].get('TailscaleIPs',[]) if re.fullmatch(r'100\.(?:6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.[0-9]{1,3}\.[0-9]{1,3}',ip)]
    if len(ips)!=1:raise SystemExit('Pilot readiness peer address refused')
    for account in ['runneradmin','devbox']:
        script=r'''$ErrorActionPreference='Stop'
$run='RUN_ID';$sha='SOURCE_SHA';$account='ACCOUNT'
$dir='C:\ProgramData\WindowsHomePilotRepair\'+$run
$metadata=Get-Content -LiteralPath (Join-Path $dir 'access.json') -Raw|ConvertFrom-Json
if($metadata.runId -cne $run -or $metadata.sourceSha -cne $sha -or $metadata.account -cne $account){throw 'Pilot readiness identity mismatch'}
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$principal=New-Object Security.Principal.WindowsPrincipal($identity)
if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) -or $identity.Name -inotlike ('*\'+$account)){throw 'Pilot readiness requires existing elevated owner account'}
[ordered]@{schema=1;runId=$run;sourceSha=$sha;account=$account;admin=$true}|ConvertTo-Json -Compress|Set-Content -LiteralPath (Join-Path $dir 'ready.json') -Encoding utf8
Write-Output 'PILOT_REPAIR_CLIENT_AUTHENTICATED=true'
'''.replace('RUN_ID',run).replace('SOURCE_SHA',sha).replace('ACCOUNT',account)
        try:
            client=winrm.Session('http://'+ips[0]+':5985/wsman',auth=(account,password),transport='ntlm',message_encryption='always',operation_timeout_sec=10,read_timeout_sec=15)
            result=client.run_ps(script)
            if result.status_code==0 and b'PILOT_REPAIR_CLIENT_AUTHENTICATED=true' in result.std_out:verified=True;break
            last_failure={'class':'native-readiness','exitCode':result.status_code,'stderr':result.std_err.decode(errors='replace')[-4096:]}
        except Exception as error:
            if last_failure.get('class')!='native-readiness':last_failure={'class':type(error).__name__}  # Never print credential-bearing errors; retry the bounded readiness race.
    if not verified:time.sleep(5)
if not verified:
    print('PILOT_REPAIR_CLIENT_FAILURE_CLASS='+last_failure['class'])
    if os.environ.get('PILOT_RSA_MODULUS'):
        from cryptography.hazmat.primitives.asymmetric import rsa,padding
        from cryptography.hazmat.primitives import hashes
        key=rsa.RSAPublicNumbers(65537,int.from_bytes(base64.b64decode(os.environ['PILOT_RSA_MODULUS']),'big')).public_key()
        raw=json.dumps({'runId':run,'kind':'repair-readiness','failure':last_failure}).encode()
        for index,offset in enumerate(range(0,len(raw),120)):
            cipher=key.encrypt(raw[offset:offset+120],padding.OAEP(mgf=padding.MGF1(hashes.SHA256()),algorithm=hashes.SHA256(),label=None))
            print('PILOT_PAIR_'+str(index)+'='+base64.b64encode(cipher).decode())
    raise SystemExit('Independent pilot WinRM authentication did not pass; guest recovery must remain blocked')
print('PILOT_REPAIR_CLIENT_AUTHENTICATED=true')
