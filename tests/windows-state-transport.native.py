"""Tiny manual transport diagnostic; publishes only random non-user probe data."""
import os,pathlib,sys,tempfile,uuid,json
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/'scripts'))
from cloud_checkpoint import GitHubRemote,CheckpointError,digest,PART_BYTES
if os.environ.get('GITHUB_ACTIONS')!='true' or os.environ.get('DEVBOX_ISOLATED_TEST')!='1' or os.environ.get('GITHUB_EVENT_NAME')!='workflow_dispatch':
    raise CheckpointError('Isolated manual CI transport probe only')
remote=GitHubRemote(os.environ['GITHUB_REPOSITORY'],'ci-'+os.environ['GITHUB_RUN_ID']+'-'+os.environ['GITHUB_RUN_ATTEMPT'])
tag='devbox-transport-probe-ci-'+os.environ['GITHUB_RUN_ID']+'-'+os.environ['GITHUB_RUN_ATTEMPT']+'-'+uuid.uuid4().hex
remote.create_draft(tag)
print('TRANSPORT PROBE DRAFT CREATE + ID LOOKUP: PASS',flush=True)
with tempfile.TemporaryDirectory() as directory:
    root=pathlib.Path(directory);sample=root/'part-0000.bin'
    size=PART_BYTES if os.environ.get('WINDOWS_STATE_TRANSPORT_FULL_PART')=='true' else 32
    with sample.open('xb') as stream:
        remaining=size
        while remaining:
            count=min(16*1024**2,remaining);stream.write(os.urandom(count));remaining-=count
    remote.upload(tag,sample)
    output=root/'readback.bin';remote.download(tag,sample.name,output,size)
    if output.stat().st_size!=size or digest(output)!=digest(sample):raise CheckpointError('Tiny draft readback mismatch')
remote.finish(tag)
print(json.dumps({'transportProbe':True,'draft':False,'tag':tag,'createUploadReadbackPublish':True,'bytes':size,'publishedCheckpoint':False}),flush=True)
