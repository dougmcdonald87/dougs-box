import json,pathlib,re,shutil,subprocess,tempfile,time,unittest
ROOT=pathlib.Path(__file__).resolve().parents[1]
PWSH=shutil.which('pwsh')
class RequestWaitTests(unittest.TestCase):
 def test_console_cutoff_matches_first_party_hold(self):
  console=(ROOT/'scripts/windows-home-console.ps1').read_text()
  hold=(ROOT/'.github/actions/pilot-device/hold-operator.mjs').read_text()
  self.assertEqual(int(re.search(r'AddMinutes\((\d+)\)',console).group(1)),int(re.search(r'maxMs=(\d+)\*60\*1000',hold).group(1)))
 @unittest.skipUnless(PWSH,'Requires native pwsh for client execution')
 def test_pending_timeout_preserves_request_and_never_claims_success(self):
  with tempfile.TemporaryDirectory() as d:
   root=self.setup(d)
   p=self.start(root,1);out,err=p.communicate(timeout=12)
   self.assertEqual(p.returncode,0,err)
   self.assertIn('still pending',out.lower())
   self.assertNotIn('VERIFIED ENCRYPTED GENERATION:',out)
   self.assertEqual(len(list((root/'requests').glob('request-*.json'))),1)
 @unittest.skipUnless(PWSH,'Requires native pwsh for client execution')
 def test_exact_verified_receipt_ends_wait(self):self.receipt_case('verified',True,0)
 @unittest.skipUnless(PWSH,'Requires native pwsh for client execution')
 def test_failed_receipt_is_reported_as_failure(self):self.receipt_case('failed',False,1)
 @unittest.skipUnless(PWSH,'Requires native pwsh for client execution')
 def test_expired_session_submits_nothing(self):
  with tempfile.TemporaryDirectory() as d:
   root=self.setup(d,expired=True);p=self.start(root,1);out,err=p.communicate(timeout=10)
   self.assertNotEqual(p.returncode,0)
   self.assertEqual(list((root/'requests').iterdir()),[])
 def setup(self,d,expired=False):
  root=pathlib.Path(d);(root/'requests').mkdir();(root/'responses').mkdir()
  (root/'session.json').write_text(json.dumps({'schema':1,'runId':'123','vmId':'22222222-2222-4222-8222-222222222222','generation':'devbox-checkpoint-v1-ci-100-1-20261014T190000Z-'+'a'*32,'deadlineMs':int(time.time()*1000)+(-1000 if expired else 60000)}))
  return root
 def start(self,root,seconds):
  return subprocess.Popen([PWSH,'-NoProfile','-File',str(ROOT/'scripts/windows-home-request.ps1'),'-Operation','Save','-ControlDir',str(root),'-WaitSeconds',str(seconds)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
 def receipt_case(self,status,verified,expected):
  with tempfile.TemporaryDirectory() as d:
   root=self.setup(d);p=self.start(root,12)
   try:
    end=time.monotonic()+5
    files=[]
    while time.monotonic()<end and p.poll() is None:
     files=list((root/'requests').glob('request-*.json'))
     if files:break
     time.sleep(.02)
    self.assertEqual(len(files),1)
    req=json.loads(files[0].read_text());receipt={'status':status,'verified':verified,'generation':'devbox-checkpoint-v1-ci-123-1-20261014T190000Z-'+'b'*32,'reason':'test-failure'}
    (root/'responses'/('response-'+req['operationId']+'.json')).write_text(json.dumps(receipt))
    out,err=p.communicate(timeout=15)
    self.assertEqual(p.returncode==0,expected==0,err)
    self.assertEqual('VERIFIED ENCRYPTED GENERATION:' in out,verified)
   finally:
    if p.poll() is None:p.kill();p.communicate()
if __name__=='__main__':unittest.main()
