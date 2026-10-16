import pathlib
import unittest

ROOT=pathlib.Path(__file__).resolve().parents[1]
SCRIPT=ROOT/'scripts'/'windows-home-restricted-agent.ps1'
SUPERVISOR=ROOT/'.github'/'actions'/'pilot-device'/'supervise-restricted.mjs'
WORKFLOW=ROOT/'.github'/'workflows'/'windows-state-probe-validate.yml'

class WorkflowSecurity(unittest.TestCase):
 def test_restricted_agent_probe_before_device_code(self):
  s=SCRIPT.read_text(encoding='utf-8')
  self.assertIn('LaunchAgent',s)
  self.assertIn('npx --yes @wonderwhy-er/desktop-commander@0.2.52 remote --no-persist-session',s)
  self.assertLess(s.index('controllDenied -ne $true'),s.index('npx --yes @wonderwhy-er/desktop-commander'))
 def test_supervisor_never_directly_spawns_privileged_remote_agent(self):
  s=SUPERVISOR.read_text(encoding='utf-8')
  self.assertIn('windows-home-restricted-agent.ps1',s)
  self.assertIn('LaunchAgent',s)
  self.assertIn('holdOperatorSession',s)
  self.assertIn('publicEncrypt',s)
  self.assertNotIn('cmd.exe',s)
  self.assertNotIn('npx --yes',s)
  self.assertIn('WINDOWS_HOME_CONTROL_DIR',s)
 def test_restore_hold_integrates_pairing_after_guest_restore_in_same_job(self):
  s=WORKFLOW.read_text(encoding='utf-8')
  block=s.split('\n  restore-hold:',1)[-1]
  self.assertIn('supervise-restricted.mjs',block)
  self.assertNotIn('node .github/actions/pilot-device/hold-operator.mjs',block)
  self.assertIn('npm install --prefix .github/actions/pilot-device',block)
  self.assertLess(block.index('Restore, boot and verify isolated Windows 10 Home guest'),block.index('supervise-restricted.mjs'))
  self.assertIn('PILOT_RSA_MODULUS',block)
 def test_no_automatic_dispatch(self):
  s=WORKFLOW.read_text(encoding='utf-8')
  self.assertIn('workflow_dispatch:',s)
  self.assertNotIn('repository_dispatch:',s)
  self.assertNotIn('schedule:',s)
if __name__=='__main__': unittest.main(verbosity=2)
