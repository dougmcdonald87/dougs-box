from pathlib import Path
import unittest
SCRIPT=Path(__file__).resolve().parents[1]/'scripts/windows-home-tailnet-oidc.ps1'
class PilotTailnetPolicyTests(unittest.TestCase):
 def test_pilot_identity_does_not_reuse_main_workflow_binding(self):
  source=SCRIPT.read_text(encoding='utf-8-sig')
  self.assertIn('refs/heads/pilot/windows-home-connection-20261015',source)
  self.assertIn('.github/workflows/windows-state-probe-validate.yml',source)
  self.assertIn("$claims.workflow_ref -cne $expectedWorkflow",source)
  self.assertIn("$claims.sub -cne $expectedSubject",source)
  self.assertIn("$claims.aud -cne $audience",source)
  self.assertIn("$env:GITHUB_EVENT_NAME -cne 'workflow_dispatch'",source)
  self.assertNotIn('devbox.yml@refs/heads/main',source)
  self.assertNotIn('Tf3m25iN2121CNTRL-k1fB6QfG2V11CNTRL',source)
if __name__=='__main__':unittest.main()
