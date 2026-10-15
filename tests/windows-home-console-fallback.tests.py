from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]/'scripts'
class RdpAccountFallback(unittest.TestCase):
 def test_console_uses_effective_rdp_account_from_setup(self):
  setup=(ROOT/'configure-rdp.ps1').read_text(encoding='utf-8-sig')
  console=(ROOT/'windows-home-console.ps1').read_text(encoding='utf-8-sig')
  self.assertIn("$acct = 'devbox'",setup,'RDP setup has the fallback branch')
  self.assertIn('rdpAccounts=$acct',setup)
  self.assertIn("Join-Path $env:DEVBOX_CONTROL_PATH 'rdp-state.txt'",console)
  self.assertIn("@('runneradmin','devbox')",console)
  self.assertIn('Get-LocalUser -Name $effectiveRdpAccount',console)
  self.assertNotIn("Get-LocalUser -Name 'runneradmin'",console)
if __name__=='__main__':unittest.main()
