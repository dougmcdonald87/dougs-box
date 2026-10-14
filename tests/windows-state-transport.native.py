"""Tiny manual transport diagnostic; publishes only random non-user probe data."""
import os,pathlib,sys,tempfile,uuid,json
sys.path.insert(0,str(pathlib.Path(__file__).resolve().parents[1]/'scripts'))
from cloud_checkpoint import GitHubRemote,CheckpointError
if os.environ.get('GITHUB_ACTIONS')!='true' or os.environ.get('DEVBOX_ISOLATED_TEST')!='1' or os.environ.get('GITHUB_EVENT_NAME')!='workflow_dispatch':
    raise CheckpointError('Isolated manual CI transport probe only')
remote=GitHubRemote(os.environ['GITHUB_REPOSITORY'],'ci-'+os.environ['GITHUB_RUN_ID']+'-'+os.environ['GITHUB_RUN_ATTEMPT'])
tag='devbox-transport-probe-ci-'+os.environ['GITHUB_RUN_ID']+'-'+os.environ['GITHUB_RUN_ATTEMPT']+'-'+uuid.uuid4().hex
remote.create_draft(tag)
print('TRANSPORT PROBE DRAFT CREATE + ID LOOKUP: PASS',flush=True)
with tempfile.TemporaryDirectory() as directory:
    root=pathlib.Path(directory);sample=root/'part-0000.bin';sample.write_bytes(os.urandom(32))
    remote.upload(tag,sample)
    output=root/'readback.bin';remote.download(tag,sample.name,output,32)
    if output.read_bytes()!=sample.read_bytes():raise CheckpointError('Tiny draft readback mismatch')
remote.finish(tag)
print(json.dumps({'transportProbe':True,'draft':False,'tag':tag,'createUploadReadbackPublish':True,'publishedCheckpoint':False}),flush=True)
