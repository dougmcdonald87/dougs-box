"""Guard the isolated pilot's public Tailscale Client ID against missing vars and trust drift."""
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
WORKFLOW=ROOT/'.github/workflows/windows-state-probe-validate.yml'
OIDC=ROOT/'scripts/windows-home-tailnet-oidc.ps1'
PILOT_ID='Tf3m25iN2121CNTRL-k9nitZxGTS11CNTRL'

class PilotTailnetClientTests(unittest.TestCase):
 def test_pilot_id_is_bound_without_unset_github_repo_variable(self):
  workflow=WORKFLOW.read_text(encoding='utf-8-sig')
  hold=workflow.split('\n  restore-hold:\n',1)[1]
  self.assertIn("PILOT_TAILSCALE_OIDC_CLIENT_ID: '"+PILOT_ID+"'",hold)
  self.assertNotIn('vars.PILOT_TAILSCALE_OIDC_CLIENT_ID',hold)
  self.assertIn('oauth-client-id: ${{ env.PILOT_TAILSCALE_OIDC_CLIENT_ID }}',hold)
  self.assertIn("format('api.tailscale.com/{0}', env.PILOT_TAILSCALE_OIDC_CLIENT_ID)",hold)
  self.assertIn('tags: tag:windows-home-pilot',hold)
 def test_pilot_trust_remains_isolated_from_original_main(self):
  workflow=WORKFLOW.read_text(encoding='utf-8-sig')
  hold=workflow.split('\n  restore-hold:\n',1)[1]
  self.assertNotIn('Tf3m25iN2121CNTRL-k1fB6QfG2V11CNTRL',hold)
  oidc=OIDC.read_text(encoding='utf-8-sig')
  self.assertIn('refs/heads/pilot/windows-home-connection-20261015',oidc)
  self.assertIn('.github/workflows/windows-state-probe-validate.yml',oidc)
  self.assertIn('$claims.workflow_ref -cne $expectedWorkflow',oidc)

if __name__=='__main__':unittest.main()
