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
