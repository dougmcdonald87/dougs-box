import ast,base64,re,types,unittest
from pathlib import Path
from unittest.mock import Mock
p=Path(__file__).with_name('pilot-repair-inspect-client.py');tree=ast.parse(p.read_text());functions=[n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name in ('make_inspection_command','run_private_script')]
ns={'re':re,'base64':base64};exec(compile(ast.Module(body=functions,type_ignores=[]),str(p),'exec'),ns)
class Private(unittest.TestCase):
 def setup_protocol(self):
  p=Mock();p.open_shell.return_value='shell';p.run_command.return_value='command';p.get_command_output.return_value=(b'{}',b'',0);return p
 def test_secret_not_command_and_skip_cmd_shell(self):
  protocol=self.setup_protocol();session=types.SimpleNamespace(protocol=protocol)
  source=Path(__file__).parent.parent.joinpath('scripts/windows-home-guest-evidence.ps1').read_text()
  command=ns['make_inspection_command']('123','a'*40,source,encoded=False)
  response=ns['run_private_script'](session,command,'owner-test-secret')
  self.assertEqual(response.status_code,0)
  protocol.open_shell.assert_called_once_with(env_vars={'PILOT_GUEST_OWNER_PASSWORD':'owner-test-secret'},codepage=65001)
  args=protocol.run_command.call_args;self.assertTrue(args.kwargs['skip_cmd_shell']);self.assertFalse(args.kwargs['console_mode_stdin'])
  self.assertNotIn('owner-test-secret',repr(args));self.assertLess(len(args.args[2][-1])+100,30000)
  self.assertLess(len(args.args[2][-1])+100,8191)
  self.assertIn('ReadToEnd',base64.b64decode(args.args[2][-1]).decode('utf-16-le'))
  protocol.send_command_input.assert_called_once_with('shell','command',command.encode('utf-8'),end=True)
  protocol.cleanup_command.assert_called_once_with('shell','command');protocol.close_shell.assert_called_once_with('shell')
 def test_shell_closed_after_output_error(self):
  protocol=self.setup_protocol();protocol.get_command_output.side_effect=RuntimeError('test')
  with self.assertRaises(RuntimeError):ns['run_private_script'](types.SimpleNamespace(protocol=protocol),'Write-Output 1','secret')
  protocol.cleanup_command.assert_called_once();protocol.close_shell.assert_called_once()
 def test_reject_oversize_before_transmitting_secret(self):
  protocol=self.setup_protocol()
  with self.assertRaises(ValueError):ns['run_private_script'](types.SimpleNamespace(protocol=protocol),'a'*70000,'secret')
  protocol.open_shell.assert_not_called()
unittest.main()
