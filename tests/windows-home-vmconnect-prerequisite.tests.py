"""Pilot must install a working Hyper-V graphical console before restoring 10 GiB."""
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
FLOW=ROOT/'.github/workflows/windows-state-probe-validate.yml'
SCRIPT=ROOT/'scripts/ensure-windows-home-vmconnect.ps1'
CONSOLE=ROOT/'scripts/windows-home-console.ps1'

class HyperVGuiToolPreflight(unittest.TestCase):
    def test_runner_provisions_gui_management_tools_before_expensive_restore(self):
        text=FLOW.read_text(encoding='utf-8-sig')
        section=text.split('\n  restore-hold:\n',1)[1]
        install=section.index('./scripts/ensure-windows-home-vmconnect.ps1')
        restore=section.index('Restore-WindowsStateRoundtrip')
        self.assertLess(install,restore)
        self.assertIn('Join tailnet using separate isolated pilot credential', section)

    def test_only_supported_gui_tools_are_installed_no_reboot(self):
        text=SCRIPT.read_text(encoding='utf-8-sig')
        self.assertIn("RSAT-Hyper-V-Tools",text)
        self.assertIn("Get-WindowsFeature",text)
        self.assertIn("Install-WindowsFeature",text)
        self.assertIn("System32\\vmconnect.exe",text)
        self.assertIn("RestartNeeded",text)
        self.assertIn("PILOT_VMCONNECT_READY=true",text)
        for forbidden in ("-Restart","Install-WindowsFeature -Name Hyper-V ","DownloadFile", "Invoke-WebRequest", "github_pat_"):
            with self.subTest(forbidden=forbidden):
                self.assertNotIn(forbidden,text)

    def test_console_shortcut_still_points_at_vmconnect(self):
        text=CONSOLE.read_text(encoding='utf-8-sig')
        self.assertIn("System32\\vmconnect.exe",text)
        self.assertIn("WINDOWS_HOME_VMCONNECT_SHORTCUT_READY",text)

if __name__=='__main__':unittest.main()
