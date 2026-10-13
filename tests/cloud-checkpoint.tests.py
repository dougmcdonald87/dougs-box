import hashlib,importlib.util,json,pathlib,tempfile,unittest,zipfile
from unittest.mock import patch

path=pathlib.Path(__file__).resolve().parents[1]/'scripts/cloud_checkpoint.py'
module=None
if path.exists():
    spec=importlib.util.spec_from_file_location('checkpoint',path)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)

class Remote:
    repository='dougmcdonald87/dougs-box'
    channel='ci-1-1'
    def __init__(self):self.records={};self.fail=None;self.corrupt=False
    def create_draft(self,tag):self.records[tag]={'draft':True,'assets':{}}
    def upload(self,tag,file):
        if self.fail=='upload':raise RuntimeError('interrupted transfer')
        self.records[tag]['assets'][file.name]=file.read_bytes()
    def download(self,tag,name,destination):
        content=self.records[tag]['assets'][name]
        if self.corrupt and name.endswith('.bin'):content=b'corrupt'
        destination.write_bytes(content)
    def finish(self,tag):
        if self.fail=='finish':raise RuntimeError('commit failed')
        self.records[tag]['draft']=False
    def generations(self):return [t for t,r in reversed(list(self.records.items())) if not r['draft']]

class CheckpointTests(unittest.TestCase):
    def setUp(self):
        self.assertIsNotNone(module,'cloud checkpoint adapter unavailable')
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.root=pathlib.Path(self.temp.name);self.remote=Remote();self.archive=self.root/'encrypted.zip'
        with zipfile.ZipFile(self.archive,'w') as z:
            z.writestr('config',b'encrypted-config');z.writestr('keys/'+'a'*64,b'wrapped-key');z.writestr('data/ab/'+'b'*64,b'encrypted-pack')
    def publish(self):return module.publish(self.archive,'a'*64,'b'*64,self.remote,part_bytes=64)
    def test_readback_before_published_generation(self):
        record=self.publish();self.assertEqual(self.remote.generations(),[record['generation']])
        got=module.fetch_latest(self.remote,self.root/'recovered.zip')
        self.assertEqual(got['snapshot_id'],'a'*64);self.assertEqual((self.root/'recovered.zip').read_bytes(),self.archive.read_bytes())
    def test_interrupted_upload_preserves_previous(self):
        old=self.publish();self.remote.fail='upload'
        with self.assertRaises(module.CheckpointError):self.publish()
        self.remote.fail=None
        self.assertEqual(module.fetch_latest(self.remote,self.root/'out.zip')['generation'],old['generation'])
    def test_corrupt_remote_readback_never_publishes(self):
        self.remote.corrupt=True
        with self.assertRaises(module.CheckpointError):self.publish()
        self.assertEqual(self.remote.generations(),[])
    def test_failed_commit_preserves_previous(self):
        old=self.publish();self.remote.fail='finish'
        with self.assertRaises(module.CheckpointError):self.publish()
        self.assertEqual(self.remote.generations(),[old['generation']])
    def test_bad_new_generation_falls_back_without_overwriting_destination(self):
        old=self.publish();new=self.publish()
        self.remote.records[new['generation']]['assets'].pop('part-0000.bin')
        result=module.fetch_latest(self.remote,self.root/'out.zip')
        self.assertEqual(result['generation'],old['generation'])
    def test_no_valid_generation_preserves_existing_destination(self):
        p=self.root/'out.zip';p.write_bytes(b'previous')
        with self.assertRaises(module.CheckpointError):module.fetch_latest(self.remote,p)
        self.assertEqual(p.read_bytes(),b'previous')
    def test_oversize_refused_before_cloud_mutation(self):
        with self.assertRaises(module.CheckpointError):module.publish(self.archive,'a'*64,'b'*64,self.remote,max_bytes=1)
        self.assertEqual(self.remote.records,{})
    def test_plaintext_project_archive_refused(self):
        with zipfile.ZipFile(self.archive,'w') as z:z.writestr('AppData/settings.json','private')
        with self.assertRaises(module.CheckpointError):self.publish()
        self.assertEqual(self.remote.records,{})
    def test_traversal_refused_before_cloud_mutation(self):
        with zipfile.ZipFile(self.archive,'a') as z:z.writestr('../secret',b'x')
        with self.assertRaises(module.CheckpointError):self.publish()
        self.assertEqual(self.remote.records,{})
    def test_wrong_repository_manifest_refused(self):
        record=self.publish();assets=self.remote.records[record['generation']]['assets']
        m=json.loads(assets['checkpoint.json']);m['repository']='other/repo';assets['checkpoint.json']=json.dumps(m).encode()
        with self.assertRaises(module.CheckpointError):module.fetch_latest(self.remote,self.root/'out.zip')
    def test_caller_crypto_verification_must_pass_before_destination_changes(self):
        self.publish();p=self.root/'out.zip';p.write_bytes(b'old')
        with self.assertRaises(module.CheckpointError):module.fetch_latest(self.remote,p,verify=lambda _:False)
        self.assertEqual(p.read_bytes(),b'old')
    def test_duplicate_zip_entries_refused(self):
        with zipfile.ZipFile(self.archive,'a') as z:z.writestr('CONFIG',b'duplicate')
        with self.assertRaises(module.CheckpointError):self.publish()
    def test_ci_generations_cannot_be_restored_as_production(self):
        self.publish();self.remote.channel='production'
        with self.assertRaises(module.CheckpointError):module.fetch_latest(self.remote,self.root/'out.zip')
    def test_archive_change_after_hash_refused_before_cloud_mutation(self):
        real_digest=module.digest;changed=False
        def race(path):
            nonlocal changed
            value=real_digest(path)
            if pathlib.Path(path)==self.archive and not changed:
                changed=True
                with zipfile.ZipFile(self.archive,'w') as z:
                    z.writestr('config',b'ENCRYPTED-config');z.writestr('keys/'+'a'*64,b'wrapped-key');z.writestr('data/ab/'+'b'*64,b'encrypted-pack')
            return value
        with patch.object(module,'digest',side_effect=race):
            with self.assertRaises(module.CheckpointError):self.publish()
        self.assertEqual(self.remote.records,{})

if __name__=='__main__':unittest.main()
