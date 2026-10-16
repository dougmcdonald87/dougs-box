"""Isolated guest owner sign-in after verified Windows Home recovery.

Source/config regression only; live guest PowerShell Direct & GUI need a Windows run.
"""
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
SCRIPT=ROOT/'scripts/windows-home-owner-account.ps1'
WORKFLOW=ROOT/'.github/workflows/windows-state-probe-validate.yml'

class GuestOwnerAccountTest(unittest.TestCase):
    def test_scope_and_owned_running_guest_guards(self):
        s=SCRIPT.read_text(encoding='utf-8-sig')
        for term in (
            "refs/heads/pilot/windows-home-connection-20261015",
            "DEVBOX_ISOLATED_TEST",
            "GITHUB_EVENT_NAME",
            "GITHUB_REPOSITORY",
            "Get-WindowsStateCheckpointOwner",
            "Get-WindowsStatePortableFixtureCredential",
            "Running",
        ):
            with self.subTest(term=term): self.assertIn(term,s)

    def test_login_account_created_in_guest_without_touching_fixture(self):
        s=SCRIPT.read_text(encoding='utf-8-sig')
        for term in ("New-PSSession -VMId", "Invoke-Command -Session",
                     "New-LocalUser", "'PilotOwner'", "Get-LocalGroup",
                     "S-1-5-32-544", "Add-LocalGroupMember",
                     "PILOT_GUEST_OWNER_LOGIN_VERIFIED=PilotOwner"):
            with self.subTest(term=term): self.assertIn(term,s)
        self.assertNotIn("Set-LocalUser -Name 'DevBoxFixture'",s)
        self.assertNotIn("New-LocalUser -Name 'DevBoxFixture'",s)

    def test_secret_not_disclosed_or_placed_in_source(self):
        s=SCRIPT.read_text(encoding='utf-8-sig')
        self.assertIn("ConvertTo-SecureString $env:DEVBOX_RDP_PASSWORD -AsPlainText -Force",s)
        for forbidden in ("github_pat_","Write-Output $env:DEVBOX_RDP_PASSWORD",
                          "Write-Host $env:DEVBOX_RDP_PASSWORD",
                          "RESTIC_PASSWORD=","Fixture!1"):
            with self.subTest(forbidden=forbidden):self.assertNotIn(forbidden,s)

    def test_flow_requires_owner_credential_before_shortcuts(self):
        w=WORKFLOW.read_text(encoding='utf-8-sig').split('\n  restore-hold:\n',1)[1]
        section=w.split("      - name: Restore, boot and verify",1)[1].split("      - name: Hold guest",1)[0]
        self.assertIn("DEVBOX_RDP_PASSWORD: ${{ secrets.DEVBOX_RDP_PASSWORD }}",section)
        self.assertIn("RESTIC_PASSWORD: ${{ secrets.RESTIC_PASSWORD }}",section)
        self.assertLess(section.index("Restore-WindowsStateRoundtrip"),
                        section.index("./scripts/windows-home-owner-account.ps1"))
        self.assertLess(section.index("./scripts/windows-home-owner-account.ps1"),
                        section.index("./scripts/windows-home-console.ps1"))
        self.assertIn("python ./tests/windows-home-guest-owner.tests.py",w.split("Restore, boot and verify",1)[0])

if __name__ == '__main__':
    unittest.main()
