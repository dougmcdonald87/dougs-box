from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]/'scripts'
class RdpAccountFallback(unittest.TestCase):
 def test_console_uses_effective_rdp_account_from_setup(self):
  setup=(ROOT/'configure-rdp.ps1').read_text(encoding='utf-8-sig')
  console=(ROOT/'windows-home-console.ps1').read_text(encoding='utf-8-sig')
  self.assertIn("$acct = 'devbox'",setup,'RDP setup has the fallback branch')
  self.assertIn('rdpAccounts=$acct',setup)
  self.assertIn("Join-Path (Join-Path $env:RUNNER_TEMP 'windows-home-restore-hold-rdp') 'rdp-state.txt'",console)
  self.assertIn("@('runneradmin','devbox')",console)
  self.assertIn('Get-LocalUser -Name $effectiveRdpAccount',console)
  self.assertNotIn("Get-LocalUser -Name 'runneradmin'",console)
  guest=(ROOT/'windows-home-guest-controls.ps1').read_text(encoding='utf-8-sig')
  self.assertIn("-NoExit -NoProfile -ExecutionPolicy Bypass",guest)
if __name__=='__main__':unittest.main()
