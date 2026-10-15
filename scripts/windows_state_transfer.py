"""Read-only exact-generation CI recovery; existing transport writer is unchanged."""
import os
import re
from cloud_checkpoint import GitHubRemote,CheckpointError,TAG

class ExactGenerationReader(GitHubRemote):
    def __init__(self,repository,generation):
        if not isinstance(repository,str) or not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+',repository) or repository!=os.environ.get('GITHUB_REPOSITORY'):
            raise CheckpointError('Recovery repository identity mismatch')
        if not os.environ.get('GH_TOKEN') or os.environ.get('DEVBOX_ISOLATED_TEST')!='1' or os.environ.get('GITHUB_EVENT_NAME')!='workflow_dispatch':
            raise CheckpointError('Recovery requires an isolated manual authenticated test')
        current=os.environ.get('GITHUB_RUN_ID','')
        if not re.fullmatch(r'\d+',current):raise CheckpointError('Recovery run identity unavailable')
        match=TAG.fullmatch(generation) if isinstance(generation,str) else None
        if not match or match.group(1)=='production':raise CheckpointError('Only an exact CI generation can be recovered')
        channel=match.group(1)
        source=re.fullmatch(r'ci-(\d+)-(\d+)',channel)
        if not source or source.group(1)==current:raise CheckpointError('Recovery must use an independently fresh run')
        self.repository=repository;self.channel=channel;self.generation=generation;self.drafts={}
    def generations(self):return [self.generation]
    def download(self,tag,name,destination,max_bytes):
        if tag!=self.generation:raise CheckpointError('Unexpected recovery generation refused')
        return super().download(tag,name,destination,max_bytes)
    def call(self,*args):raise CheckpointError('Read-only recovery cannot modify releases')
    def create_draft(self,tag):raise CheckpointError('Read-only recovery cannot create releases')
    def upload(self,tag,path):raise CheckpointError('Read-only recovery cannot upload')
    def finish(self,tag):raise CheckpointError('Read-only recovery cannot publish')

def validate_transfer_record(value,expected_generation,current_host,current_run):
    """Bind authenticated fixture metadata to its exact producer and a fresh host."""
    import uuid
    def guid(item):
        try:
            parsed=uuid.UUID(item)
            if not parsed.int or str(parsed)!=item.lower():raise ValueError()
            return str(parsed)
        except (ValueError,TypeError,AttributeError):raise CheckpointError('Invalid transfer host/VM identity') from None
    fields={'schema','producer_run','producer_attempt','producer_host','source_sha','vm_id','vm_name','root','generation','manifest_sha256','baseline'}
    if not isinstance(value,dict) or set(value) not in (fields,fields|{'origin_generation'}) or type(value['schema']) is not int or value['schema']!=1:
        raise CheckpointError('Invalid transfer record schema')
    match=TAG.fullmatch(expected_generation) if isinstance(expected_generation,str) else None
    source=re.fullmatch(r'ci-([1-9]\d*)-([1-9]\d*)',match.group(1)) if match else None
    if not source or value['producer_run']!=source.group(1) or value['producer_attempt']!=source.group(2):
        raise CheckpointError('Transfer producer generation mismatch')
    if not isinstance(current_run,str) or not re.fullmatch(r'[1-9]\d*',current_run) or current_run==value['producer_run']:
        raise CheckpointError('Transfer consumer run must be distinct')
    if guid(value['producer_host'])==guid(current_host):raise CheckpointError('Transfer consumer host must be distinct')
    guid(value['vm_id'])
    if 'origin_generation' in value:
        origin=TAG.fullmatch(value['origin_generation']) if isinstance(value['origin_generation'],str) else None
        chain=re.fullmatch(r'ci-([1-9]\d*)-([1-9]\d*)',origin.group(1)) if origin else None
        if not chain:raise CheckpointError('Interactive origin generation mismatch')
        suffix=chain.group(1)+'-'+chain.group(2)
    else:
        suffix=value['producer_run']+'-'+value['producer_attempt']
    if value['vm_name']!='DevBoxWindowsState-'+suffix or value['root']!='E:/DevBox/Tools/WindowsStateProbe/probe-'+suffix:
        raise CheckpointError('Transfer owner scope mismatch')
    mode_pattern=r'(save|finish)-[0-9a-f]{32}' if 'origin_generation' in value else r'finish-[0-9a-f]{32}'
    for field,pattern in [('generation',mode_pattern),('manifest_sha256',r'[0-9a-f]{64}'),('source_sha',r'[0-9a-f]{40}')]:
        if not isinstance(value[field],str) or not re.fullmatch(pattern,value[field]):raise CheckpointError('Invalid transfer generation/digest')
    baseline=value['baseline']
    if not isinstance(baseline,dict) or set(baseline)!={'machineName','machineGuid','programPath','programVersion','documentSha256','preferences','windowsHideFileExt'}:
        raise CheckpointError('Invalid transfer baseline schema')
    guid(baseline['machineGuid'])
    if not isinstance(baseline['machineName'],str) or not re.fullmatch(r'[A-Za-z0-9-]{1,15}',baseline['machineName']):raise CheckpointError('Invalid fixture machine name')
    if baseline['programPath']!=r'C:\DevBoxFixture\Python312\python.exe' or baseline['programVersion']!='Python 3.12.10':raise CheckpointError('Unexpected fixture executable')
    if not isinstance(baseline['documentSha256'],str) or not re.fullmatch(r'[0-9A-Fa-f]{64}',baseline['documentSha256']):raise CheckpointError('Invalid fixture document digest')
    if type(baseline['windowsHideFileExt']) is not int or baseline['windowsHideFileExt'] not in (0,1):raise CheckpointError('Invalid fixture Windows preference')
    prefs=baseline['preferences']
    if not isinstance(prefs,dict) or set(prefs)!={'theme','volume'} or prefs['theme'] not in ('light','dark') or type(prefs['volume']) is not int or not 0<=prefs['volume']<=100:
        raise CheckpointError('Invalid fixture application preferences')
    return value

if __name__=='__main__':
    import argparse,json
    from pathlib import Path
    from cloud_checkpoint import fetch_latest,crypto_verify
    parser=argparse.ArgumentParser()
    parser.add_argument('operation',choices=['fetch','verify-record'])
    parser.add_argument('--generation',required=True)
    parser.add_argument('--archive');parser.add_argument('--restic-exe')
    parser.add_argument('--record');parser.add_argument('--host');parser.add_argument('--run')
    args=parser.parse_args()
    try:
        if args.operation=='fetch':
            if not args.archive or not args.restic_exe:raise CheckpointError('Recovery archive and Restic required')
            remote=ExactGenerationReader(os.environ.get('GITHUB_REPOSITORY',''),args.generation)
            value=fetch_latest(remote,args.archive,verify=lambda path,record:crypto_verify(path,args.restic_exe,record))
            if value['generation']!=args.generation:raise CheckpointError('Accepted recovery generation mismatch')
        else:
            if not args.record or not args.host or not args.run:raise CheckpointError('Recovery record and current host/run required')
            path=Path(args.record)
            if path.is_symlink() or not 0<path.stat().st_size<=1024**2:raise CheckpointError('Invalid transfer record file/size')
            value=validate_transfer_record(json.loads(path.read_text(encoding='utf-8-sig')),args.generation,args.host,args.run)
        print(json.dumps(value,separators=(',',':')))
    except Exception as error:
        detail=str(error) if isinstance(error,CheckpointError) else type(error).__name__
        parser.exit(2,'Windows state transfer refused ('+detail+'); no restore success claimed.\n')
