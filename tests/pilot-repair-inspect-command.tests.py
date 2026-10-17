import ast,base64,gzip,re,unittest
from pathlib import Path
path=Path(__file__).with_name('pilot-repair-inspect-client.py')
tree=ast.parse(path.read_text());functions=[n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='make_inspection_command']
if not functions:raise AssertionError('Missing short host-checkout inspection command')
ns={'re':re,'base64':base64};exec(compile(ast.Module(body=functions,type_ignores=[]),str(path),'exec'),ns)
class Command(unittest.TestCase):
 def test_native_command_limit(self):
  source=Path(__file__).parent.parent.joinpath('scripts/windows-home-repair-inspect.ps1').read_text()
  old='powershell -EncodedCommand '+base64.b64encode(source.encode('utf-16-le')).decode()
  self.assertGreater(len(old),8191)
  command=ns['make_inspection_command']('39073421057','a'*40,source)
  actual='powershell -EncodedCommand '+base64.b64encode(command.encode('utf-16-le')).decode()
  self.assertLess(len(actual),8191);self.assertIn('GZipStream',command)
 def test_exact_payload_roundtrip(self):
  source="Write-Output '__TARGET_RUN__ __TARGET_SHA__'"
  cmd=ns['make_inspection_command']('123','a'*40,source)
  packed=re.search("FromBase64String\\('([^']+)'\\)",cmd).group(1)
  self.assertEqual(gzip.decompress(base64.b64decode(packed)).decode(),source.replace('__TARGET_RUN__','123').replace('__TARGET_SHA__','a'*40))
 def test_injection_refused(self):
  with self.assertRaises(ValueError):ns['make_inspection_command']("123';whoami",'a'*40,'script')
unittest.main()
