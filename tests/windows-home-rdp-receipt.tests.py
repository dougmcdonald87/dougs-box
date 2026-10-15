"""Protect pilot RDP account receipt against bootstrap's DEVBOX_CONTROL_PATH reassignment."""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
RUNNER_CONTROL = "windows-home-restore-hold-rdp"

class WindowsHomeRdpReceiptTests(unittest.TestCase):
    def test_bootstrap_rewrites_mutable_control_env(self):
        source = (ROOT / "scripts/bootstrap.ps1").read_text(encoding="utf-8-sig")
        self.assertIn("$env:DEVBOX_CONTROL_PATH  = (Join-Path $wsRoot 'Control')", source)
        self.assertIn("'DEVBOX_WSROOT', 'DEVBOX_CONTROL_PATH'", source)

    def test_rdp_setup_and_console_consumer_use_exact_same_runner_temp_path(self):
        workflow = (ROOT / ".github/workflows/windows-state-probe-validate.yml").read_text(encoding="utf-8-sig")
        consumer = (ROOT / "scripts/windows-home-console.ps1").read_text(encoding="utf-8-sig")
        setup = (ROOT / "scripts/configure-rdp.ps1").read_text(encoding="utf-8-sig")
        self.assertIn("$env:DEVBOX_CONTROL_PATH=Join-Path $env:RUNNER_TEMP 'windows-home-restore-hold-rdp'", workflow)
        self.assertIn("Join-Path $env:DEVBOX_CONTROL_PATH 'rdp-state.txt'", setup)
        # Bootstrap runs inside the restore shell and changes DEVBOX_CONTROL_PATH.
        # The later console consumer MUST independently resolve the original receipt.
        self.assertIn("Join-Path (Join-Path $env:RUNNER_TEMP 'windows-home-restore-hold-rdp') 'rdp-state.txt'", consumer)
        self.assertNotIn("Join-Path $env:DEVBOX_CONTROL_PATH 'rdp-state.txt'", consumer)

    def test_consumer_checks_receipt_and_authorized_local_account(self):
        source = (ROOT / "scripts/windows-home-console.ps1").read_text(encoding="utf-8-sig")
        self.assertIn("'RDP account setup receipt missing.'", source)
        self.assertIn("rdpAccounts=(runneradmin|devbox)", source)
        self.assertIn("Get-LocalUser -Name $effectiveRdpAccount", source)

if __name__ == "__main__":
    unittest.main()
