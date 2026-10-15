import copy,importlib.util,json,os,pathlib,subprocess,sys,tempfile,unittest
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
 def test_cli_refuses_production_fetch_before_network(self):
  result=subprocess.run([sys.executable,str(SOURCE),'fetch','--generation',TAG.replace('ci-123-1','production'),'--archive','unused.zip','--restic-exe','unavailable'],capture_output=True,text=True)
  self.assertNotEqual(result.returncode,0,'CLI must refuse a production recovery request')
 def test_cli_validates_record(self):
  with tempfile.TemporaryDirectory() as directory:
   record=pathlib.Path(directory)/'record.json';record.write_text(json.dumps(self.record()))
   result=subprocess.run([sys.executable,str(SOURCE),'verify-record','--generation',TAG,'--record',str(record),'--host','44444444-4444-4444-8444-444444444444','--run','456'],capture_output=True,text=True)
   accepted=False
   try:accepted=result.returncode==0 and json.loads(result.stdout)==self.record()
   except ValueError:pass
   self.assertTrue(accepted,'CLI must return the validated exact transfer record')
 def record(self):
  return {'schema':1,'producer_run':'123','producer_attempt':'1','producer_host':'11111111-1111-4111-8111-111111111111','source_sha':'a'*40,'vm_id':'22222222-2222-4222-8222-222222222222','vm_name':'DevBoxWindowsState-123-1','root':'E:/DevBox/Tools/WindowsStateProbe/probe-123-1','generation':'finish-'+'b'*32,'manifest_sha256':'c'*64,'baseline':{'machineName':'DESKTOP-FIXTURE','machineGuid':'33333333-3333-4333-8333-333333333333','programPath':r'C:\DevBoxFixture\Python312\python.exe','programVersion':'Python 3.12.10','documentSha256':'D'*64,'preferences':{'theme':'light','volume':84},'windowsHideFileExt':1}}
 def validate(self,record,host='44444444-4444-4444-8444-444444444444',run='456'):
  accepted=False
  try:accepted=module.validate_transfer_record(record,TAG,host,run) is record
  except (module.CheckpointError,AttributeError):pass
  return accepted
 def test_valid_fresh_host_record(self):self.assertTrue(self.validate(self.record()),'Valid exact source record must bind to a distinct host')
 def test_wrong_host_run_or_source_record_refused(self):
  for field,value in [('producer_run','999'),('producer_attempt','2'),('vm_name','Other'),('root','D:/user'),('generation','save-'+'b'*32),('manifest_sha256','bad'),('source_sha','bad')]:
   record=self.record();record[field]=value
   with self.subTest(field=field):self.assertFalse(self.validate(record))
  self.assertFalse(self.validate(self.record(),host=self.record()['producer_host']))
  self.assertFalse(self.validate(self.record(),run='123'))
 def test_secret_or_unknown_record_fields_refused(self):
  record=self.record();record['password']='fixture'
  self.assertFalse(self.validate(record))
 def test_malformed_baseline_refused(self):
  for field,value in [('programPath','D:/wrong.exe'),('documentSha256','bad'),('machineGuid','bad'),('preferences',{'theme':'light','volume':84,'secret':'x'}),('windowsHideFileExt',True)]:
   record=self.record();record['baseline'][field]=value
   with self.subTest(field=field):self.assertFalse(self.validate(record))
 def test_interactive_restored_guest_keeps_original_root(self):
  record=self.record()
  record['vm_name']='DevBoxWindowsState-999-1'
  record['root']='E:/DevBox/Tools/WindowsStateProbe/probe-999-1'
  record['origin_generation']='devbox-checkpoint-v1-ci-999-1-20261014T190000Z-'+'e'*32
  record['generation']='save-'+'b'*32
  self.assertTrue(self.validate(record))
 def test_interactive_origin_mismatch_cannot_target_another_vm(self):
  record=self.record()
  record['vm_name']='DevBoxWindowsState-999-1'
  record['root']='E:/DevBox/Tools/WindowsStateProbe/probe-999-1'
  record['origin_generation']='devbox-checkpoint-v1-ci-999-1-20261014T190000Z-'+'e'*32
  for field,value in [('vm_name','DevBoxWindowsState-888-1'),('root','D:/user'),('origin_generation',TAG),('origin_generation','production')]:
   x=copy.deepcopy(record);x[field]=value
   with self.subTest(field=field):self.assertFalse(self.validate(x))
 def test_legacy_fixture_save_stays_forbidden(self):
  record=self.record();record['generation']='save-'+'b'*32
  self.assertFalse(self.validate(record))
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
