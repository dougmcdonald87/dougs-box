"""Guard against the real Windows runner AddAccessRule SID translation failure.

Observed on GitHub Actions run 38822434581: bare SID string overload fails.
Controlled real Windows reproducer 38826328423: typed SecurityIdentifier succeeds.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
CONSOLE = ROOT / "scripts/windows-home-console.ps1"
WORKFLOW = ROOT / ".github/workflows/windows-state-probe-validate.yml"

class ControlDirectoryAclSidRegression(unittest.TestCase):
    def test_explicit_securityidentifier_used_for_acl_identity(self):
        src = CONSOLE.read_text(encoding="utf-8-sig")
        self.assertIn("[Security.Principal.SecurityIdentifier]::new($sid)", src)
        self.assertIn("[Security.AccessControl.FileSystemAccessRule]::new($principal,", src)
        self.assertNotIn("[Security.AccessControl.FileSystemAccessRule]::new($sid,", src)

    def test_directory_restricts_inheritance_and_verifies_applied_sids(self):
        src = CONSOLE.read_text(encoding="utf-8-sig")
        self.assertIn("$acl.SetAccessRuleProtection($true,$false)", src)
        self.assertIn("Set-Acl -LiteralPath $dir -AclObject $acl", src)
        self.assertIn("GetAccessRules($true,$false,[Security.Principal.SecurityIdentifier])", src)
        self.assertIn("'S-1-5-18'", src)
        self.assertIn("$rdpUser.SID.Value", src)

    def test_preflight_runs_before_download_of_encrypted_guest(self):
        src = WORKFLOW.read_text(encoding="utf-8-sig").split("\n  restore-hold:\n",1)[1]
        call = src.index("python ./tests/windows-home-sid-acl.tests.py")
        restore = src.index("Restore-WindowsStateRoundtrip")
        self.assertLess(call, restore)

if __name__ == "__main__":
    unittest.main()
