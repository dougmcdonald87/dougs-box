import pathlib, unittest
root=pathlib.Path(__file__).resolve().parents[1]
class NativeIsolationHarness(unittest.TestCase):
 def test_dedicated_manual_window_probe_does_not_run_guest(self):
  wf=(root/'.github/workflows/windows-state-probe-validate.yml').read_text() if (root/'.github/workflows/windows-state-probe-validate.yml').exists() else ''
  self.assertIn('restricted-agent-probe',wf)
  self.assertIn('windows-home-native-isolation.probe.ps1',wf)
  self.assertNotIn('schedule:',wf)
 def test_native_harness_uses_synthetic_acl_and_no_real_secrets(self):
  p=root/'tests/windows-home-native-isolation.probe.ps1';src=p.read_text() if p.exists() else ''
  for marker in ['GITHUB_WORKSPACE','WindowsHomePilot','SetAccessRuleProtection','S-1-5-18','S-1-5-32-544','windows-home-restricted-agent.ps1','PILOT_RESTRICTED_IDENTITY_SENTINEL_DENIAL_OK=true']:
   self.assertIn(marker,src)
  self.assertNotIn('DEVBOX_RDP_PASSWORD',src)
  self.assertNotIn('RESTIC_PASSWORD',src)
if __name__=='__main__': unittest.main(verbosity=2)
