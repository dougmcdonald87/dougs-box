import importlib.util,os,pathlib,sys,unittest
from unittest.mock import patch
SOURCE=pathlib.Path(__file__).resolve().parents[1]/'scripts/windows_state_transfer.py'
sys.path.insert(0,str(SOURCE.parent))
module=None
if SOURCE.exists():
 spec=importlib.util.spec_from_file_location('windows_state_transfer',SOURCE)
 module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
TAG='devbox-checkpoint-v1-ci-123-1-20261014T190000Z-'+'a'*32
class ExactGenerationReaderTests(unittest.TestCase):
 def setUp(self):
  self.assertIsNotNone(module,'Read-only exact-generation recovery adapter missing')
  self.env=patch.dict(os.environ,{'GITHUB_REPOSITORY':'owner/repo','GH_TOKEN':'fixture-token','DEVBOX_ISOLATED_TEST':'1','GITHUB_EVENT_NAME':'workflow_dispatch','GITHUB_RUN_ID':'456'},clear=True)
  self.env.start();self.addCleanup(self.env.stop)
 def reader(self,tag=TAG,repository='owner/repo'):return module.ExactGenerationReader(repository,tag)
 def test_exact_source_generation_only(self):
  r=self.reader();self.assertEqual(r.generations(),[TAG]);self.assertEqual(r.channel,'ci-123-1')
 def test_all_mutation_routes_refused_before_command(self):
  r=self.reader()
  with patch('cloud_checkpoint.subprocess.run',side_effect=AssertionError('Command must not execute')):
   for action,args in [('call',('release','delete',TAG)),('create_draft',(TAG,)),('upload',(TAG,'fixture.bin')),('finish',(TAG,))]:
    with self.subTest(action=action):
     with self.assertRaises(module.CheckpointError):getattr(r,action)(*args)
 def test_wrong_generation_refused_before_download(self):
  r=self.reader()
  with patch('cloud_checkpoint.GitHubRemote.download',side_effect=AssertionError('Must not download')):
   with self.assertRaises(module.CheckpointError):r.download(TAG[:-1]+'b','checkpoint.json','fixture',1024)
 def test_production_channel_refused(self):
  with self.assertRaises(module.CheckpointError):self.reader(TAG.replace('ci-123-1','production'))
 def test_same_source_run_refused(self):
  with patch.dict(os.environ,{'GITHUB_RUN_ID':'123'}):
   with self.assertRaises(module.CheckpointError):self.reader()
 def test_repository_mismatch_refused(self):
  with self.assertRaises(module.CheckpointError):self.reader(repository='other/repo')
 def test_invalid_tag_refused(self):
  for tag in ('','production','../fixture',TAG+'extra'):
   with self.subTest(tag=tag):
    with self.assertRaises(module.CheckpointError):self.reader(tag)
 def test_context_guards(self):
  for key,value in [('GH_TOKEN',''),('DEVBOX_ISOLATED_TEST','0'),('GITHUB_EVENT_NAME','pull_request'),('GITHUB_RUN_ID','')]:
   with self.subTest(key=key),patch.dict(os.environ,{key:value}):
    with self.assertRaises(module.CheckpointError):self.reader()
 def test_existing_writer_cross_run_guard_remains(self):
  import cloud_checkpoint
  with self.assertRaises(module.CheckpointError):cloud_checkpoint.GitHubRemote('owner/repo','ci-123-1')
if __name__=='__main__':unittest.main()
