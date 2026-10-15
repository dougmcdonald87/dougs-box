# Windows Home guest access evidence — 2026-10-15

Status: Task 1 read-only inspection. No new live workflow was started.

Observed on pilot branch: `scripts/configure-rdp.ps1` enables TermService and TCP/3389 for the outer runner, with NLA and Tailscale-address firewall restriction. The `operator` and `restore-hold` jobs invoke this script as a runner step, outside the Hyper-V guest. `restore-hold` subsequently calls `Restore-WindowsStateRoundtrip -HoldForOperator`, verifies a booted guest, and starts `.github/actions/pilot-device/index.mjs`, which launches Desktop Commander remote on the runner. None of these operations provides direct proof of a guest graphical desktop on an iPhone.

Falsifier: host RDP ready and Desktop Commander paired while guestScreenVisible=false. This must fail guest-graphical-access acceptance even when the guest is booted and PowerShell Direct verifies it.

Prove Me Wrong verdict: FALSIFIED for the narrow claim 'host RDP and paired Desktop Commander alone establish iPhone graphical control of the Windows 10 Home guest'. The stronger claim that a console bridge or supported guest remote-control agent can work is UNVERIFIED until a controlled live test.

Required acceptance evidence: actual Windows 10 Home guest display from iPhone, successful pointer/keyboard input inside guest, and successful reconnect. Do not mistake host desktop or VM status for this evidence. No public inbound RDP; preserve original DevBox, main, D and Lenovo.

Next: select and verify an authenticated guest-console access route; add a machine-readable guard so guestScreenVisible=false always fails. Keep the canonical rolling handover ZIP updated. No long-running guest session should be represented as usable or durable until both graphical access and Save/Finish are implemented and tested.
