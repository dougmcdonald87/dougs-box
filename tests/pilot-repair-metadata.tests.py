import unittest,io,zipfile,json,hashlib,sys,types
from unittest.mock import patch
from pilot_repair_metadata import fetch_metadata
from pilot_repair_metadata import validate_metadata
class Metadata(unittest.TestCase):
 def setUp(self):self.d=dict(schema=1,runId='123',sourceSha='a'*40,hostname='windows-home-pilot-123',computerName='fv-az123-456',account='runneradmin',ip='100.84.53.44',port=5985)
 def test_configured_identity(self):self.assertEqual(validate_metadata(self.d,'123','a'*40)['computerName'],'fv-az123-456')
 def test_foreign_source(self):
  with self.assertRaises(ValueError):validate_metadata(self.d,'123','b'*40)
 def test_foreign_endpoints(self):
  for ip in ('127.0.0.1','100.128.0.1','192.168.1.2','::1'):
   with self.subTest(ip=ip),self.assertRaises(ValueError):validate_metadata(dict(self.d,ip=ip),'123','a'*40)
 def test_foreign_account(self):
  with self.assertRaises(ValueError):validate_metadata(dict(self.d,account='other'),'123','a'*40)
 def test_command_injection(self):
  with self.assertRaises(ValueError):validate_metadata(dict(self.d,computerName="a';whoami"),'123','a'*40)
class Download(Metadata):
 def test_no_token_on_storage_request(self):
  buffer=io.BytesIO()
  with zipfile.ZipFile(buffer,'w') as z:z.writestr('access.json',json.dumps(self.d))
  raw=buffer.getvalue();calls=[]
  artifact={'id':42,'name':'pilot-repair-bootstrap-123','expired':False,'workflow_run':{'id':123,'head_sha':'a'*40},'size_in_bytes':len(raw),'digest':'sha256:'+hashlib.sha256(raw).hexdigest()}
  def get(url,**kwargs):
   calls.append((url,kwargs));n=len(calls)
   if n==1:return types.SimpleNamespace(raise_for_status=lambda:None,json=lambda:{'artifacts':[artifact]})
   if n==2:return types.SimpleNamespace(status_code=302,headers={'Location':'https://storage.example/signed'})
   self.assertNotIn('headers',kwargs);self.assertNotIn('auth',kwargs)
   return types.SimpleNamespace(raise_for_status=lambda:None,iter_content=lambda n:[raw])
  with patch.dict(sys.modules,{'requests':types.SimpleNamespace(get=get)}):
   self.assertEqual(fetch_metadata('123','a'*40,'secret-token'),self.d)
  self.assertEqual(len(calls),3)
unittest.main()

