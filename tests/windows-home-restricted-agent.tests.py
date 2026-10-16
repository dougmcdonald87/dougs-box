import pathlib
import re
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'scripts' / 'windows-home-restricted-agent.ps1'

class RestrictedAgentStaticPolicy(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SCRIPT.read_text(encoding='utf-8') if SCRIPT.exists() else ''

    def test_exact_isolated_workflow_identity(self):
        for marker in ["refs/heads/pilot/windows-home-connection-20261015", "dougmcdonald87/dougs-box", "workflow_dispatch", "DEVBOX_ISOLATED_TEST"]:
            self.assertIn(marker, self.source)

    def test_uses_separate_windows_account_not_inherited_user(self):
        for marker in ['New-LocalUser', '.UserName', '.Password', 'LoadUserProfile', 'Get-LocalGroupMember', 'S-1-5-32-544', 'S-1-5-32-578']:
            self.assertIn(marker, self.source)
        self.assertNotIn('Start-Process -Verb RunAs', self.source)

    def test_actual_child_must_deny_reads(self):
        for marker in ['ChildProbe', 'WindowsIdentity', 'UnauthorizedAccessException', 'Directory]::EnumerateFileSystemEntries', 'session.json', 'controllDenied', 'guestDenied']:
            self.assertIn(marker, self.source)

    def test_secret_free_child_environment_and_fail_closed(self):
        for marker in ['.Environment.Clear()', 'RESTIC_PASSWORD', 'GH_TOKEN', 'envClean', 'throw', 'Remove-LocalUser']:
            self.assertIn(marker, self.source)
        self.assertNotRegex(self.source, r'(?i)DEVBOX_RDP_PASSWORD.*write-host')

    def test_no_mutation_of_guest_acl_or_production(self):
        self.assertNotRegex(self.source, r'(?i)Set-Acl[^\n]*(?:GuestRoot|probe-|E:|DevBox)')
        self.assertNotIn('devbox.yml', self.source)
        self.assertNotIn('production', self.source.lower())

if __name__ == '__main__': unittest.main(verbosity=2)
