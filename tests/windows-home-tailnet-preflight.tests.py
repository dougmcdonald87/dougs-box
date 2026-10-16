"""Offline, no-VM smoke test for the isolated, bounded Tailscale login phase."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github/workflows/windows-state-probe-validate.yml"
CLIENT = "Tf3m25iN2121CNTRL-k9nitZxGTS11CNTRL"
BRANCH = "pilot/windows-home-connection-20261015"

class PilotConnectionPreflight(unittest.TestCase):
    def test_short_manual_only_preflight_exists(self):
        text = WORKFLOW.read_text(encoding="utf-8-sig")
        self.assertIn("tailnet-preflight", text.split("transfer_phase:", 1)[1].split("transport_full_part:", 1)[0])
        section = text.split("\n  tailnet-preflight:\n", 1)[1].split("\n  restore-hold:\n", 1)[0]
        self.assertIn("inputs.transfer_phase == 'tailnet-preflight'", section)
        self.assertIn("runs-on: ubuntu-latest", section)
        self.assertIn("environment: devbox", section)
        self.assertIn("id-token: write", section)
        self.assertIn("contents: read", section)
        self.assertIn("timeout-minutes: 12", section)
        self.assertIn("PILOT_TAILSCALE_OIDC_CLIENT_ID: '" + CLIENT + "'", section)
        self.assertIn("tags: tag:windows-home-pilot", section)
        self.assertIn("windows-home-tailnet-oidc.ps1", section)
        self.assertIn("tailscale ip -4", section)
        for forbidden in ("Restore-WindowsStateRoundtrip", "Export-WindowsStateCheckpoint", "configure-rdp.ps1", "GH_TOKEN:", "RESTIC_PASSWORD:"):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden, section)

    def test_original_devbox_client_not_reused(self):
        text = WORKFLOW.read_text(encoding="utf-8-sig")
        section = text.split("\n  tailnet-preflight:\n", 1)[1].split("\n  restore-hold:\n", 1)[0]
        self.assertNotIn("Tf3m25iN2121CNTRL-k1fB6QfG2V11CNTRL", section)
        self.assertIn("refs/heads/" + BRANCH, section)

if __name__ == "__main__":
    unittest.main()
