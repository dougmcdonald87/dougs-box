"""Read only the public, pinned bootstrap receipt; never forward GitHub auth on redirect."""
import hashlib,io,ipaddress,json,re,zipfile
REPO='dougmcdonald87/dougs-box'
def validate_metadata(data,run,sha):
    if data.get('schema')!=1 or data.get('runId')!=run or data.get('sourceSha')!=sha or data.get('hostname')!='windows-home-pilot-'+run:
        raise ValueError('Bootstrap run/source mismatch')
    if data.get('account') not in ('runneradmin','devbox') or not re.fullmatch(r'[A-Za-z0-9-]{1,15}',data.get('computerName','')):
        raise ValueError('Bootstrap local account identity invalid')
    ip=ipaddress.ip_address(data.get('ip',''))
    if ip.version!=4 or ip not in ipaddress.ip_network('100.64.0.0/10') or str(ip)!=data['ip'] or data.get('port')!=5985:
        raise ValueError('Bootstrap endpoint outside pilot scope')
    return data

def fetch_metadata(run,sha,token):
    import requests
    root='https://api.github.com/repos/'+REPO
    headers={'Authorization':'Bearer '+token,'Accept':'application/vnd.github+json'}
    r=requests.get(root+'/actions/runs/'+run+'/artifacts',headers=headers,timeout=15);r.raise_for_status()
    artifacts=[a for a in r.json()['artifacts'] if a['name']=='pilot-repair-bootstrap-'+run and not a['expired']]
    if not artifacts:return None
    if len(artifacts)!=1:raise ValueError('Ambiguous bootstrap artifact')
    a=artifacts[0]
    if a['workflow_run']['id']!=int(run) or a['workflow_run']['head_sha']!=sha or a['size_in_bytes']>16384:
        raise ValueError('Bootstrap artifact identity/size mismatch')
    r=requests.get(root+'/actions/artifacts/'+str(int(a['id']))+'/zip',headers=headers,timeout=15,allow_redirects=False)
    if r.status_code!=302:raise ValueError('Artifact download redirect unavailable')
    location=r.headers['Location']
    if not location.startswith('https://'):raise ValueError('Insecure artifact redirect')
    # No GitHub token is attached to the signed object-storage request.
    r=requests.get(location,timeout=20,stream=True);r.raise_for_status()
    raw=bytearray()
    for chunk in r.iter_content(4096):
        raw.extend(chunk)
        if len(raw)>16384:raise ValueError('Bootstrap download too large')
    digest=a.get('digest','')
    if digest!='sha256:'+hashlib.sha256(raw).hexdigest():raise ValueError('Bootstrap digest mismatch')
    with zipfile.ZipFile(io.BytesIO(raw)) as z:
        if z.namelist()!=['access.json'] or z.getinfo('access.json').file_size>4096:raise ValueError('Bootstrap archive layout refused')
        return validate_metadata(json.loads(z.read('access.json').decode('utf-8-sig')),run,sha)
