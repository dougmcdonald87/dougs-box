import contextlib,io,json,os,runpy,sys,types,unittest
from pathlib import Path
from unittest.mock import patch
import pilot_repair_metadata
class InvalidCredentialsError(Exception):pass
class Client(unittest.TestCase):
 def exercise(self,accept,failure=InvalidCredentialsError):
  clock=[0];calls=[];receipts=[None,None,dict(account='runneradmin',computerName='host-42',ip='100.84.53.44')]
  def metadata(*args):return receipts.pop(0) if receipts else dict(account='runneradmin',computerName='host-42',ip='100.84.53.44')
  def session(endpoint,auth,**kw):
   self.assertFalse(receipts,'Attempted authentication before bootstrap receipt');calls.append(auth[0]);self.assertEqual(kw['message_encryption'],'always')
   class S:
    def run_ps(self,script):
     if auth[0]!=accept:raise failure()
     return types.SimpleNamespace(status_code=0,std_out=b'PILOT_REPAIR_CLIENT_AUTHENTICATED=true',std_err=b'')
   return S()
  peers=json.dumps({'Peer':{'p':{'HostName':'windows-home-pilot-123','TailscaleIPs':['100.84.53.44']}}}).encode()
  env=dict(GITHUB_RUN_ID='123',GITHUB_SHA='a'*40,PILOT_OWNER_PASSWORD='fixture',GH_TOKEN='fixture',PILOT_RSA_MODULUS='')
  with patch.dict(os.environ,env),patch.dict(sys.modules,{'winrm':types.SimpleNamespace(Session=session)}),patch.object(pilot_repair_metadata,'fetch_metadata',side_effect=metadata),patch('subprocess.check_output',return_value=peers),patch('time.monotonic',side_effect=lambda:clock[0]),patch('time.sleep',side_effect=lambda n:clock.__setitem__(0,clock[0]+n)),contextlib.redirect_stdout(io.StringIO()):
   try:runpy.run_path(str(Path(__file__).with_name('pilot-repair-access-client.py')))
   except SystemExit:
    if accept is not None:raise
  return calls
 def test_qualified_distinguishes_failure(self):self.assertEqual(self.exercise('host-42\\runneradmin'),['runneradmin','host-42\\runneradmin'])
 def test_bare_can_falsify_qualification_claim(self):self.assertEqual(self.exercise('runneradmin'),['runneradmin'])
 def test_wrong_credential_does_not_bruteforce(self):self.assertEqual(self.exercise(None),['runneradmin','host-42\\runneradmin']*2)
 def test_lost_response_still_consumes_attempt(self):self.assertEqual(self.exercise(None,TimeoutError),['runneradmin','host-42\\runneradmin']*2)
unittest.main()
