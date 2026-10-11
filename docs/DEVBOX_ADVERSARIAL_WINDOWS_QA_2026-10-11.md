# DevBox adversarial Windows QA — 2026-10-11

**Scope:** Isolated GitHub-hosted Windows 2025-vs2026 workers only. Do not modify Lenovo `DESKTOP-60Q2KS9` (100.70.202.110), HP, existing Z: drive, RustDesk, existing OpenCode servers, or Tailscale tags/ACLs. Preserve the original live-run logs.

## Evidence ledger (actual runs, distinct from code inspection)

| Pass | Evidence | Challenge and result |
|---|---|---|
| 1 | [Live DevBox #38148379792](https://github.com/dougmcdonald87/dougs-box/actions/runs/38148379792) | Github OIDC, Tailscale, 100 GiB+ workspace passed; OpenCode installer failed because `Invoke-DevboxRetry` read unset `$LASTEXITCODE` under StrictMode. |
| 2 | [PowerShell Validate #38149066492](https://github.com/dougmcdonald87/dougs-box/actions/runs/38149066492) | Real PowerShell regression for unset native status, stale status, transient failures and piped native nonzero; all passed after rejecting an earlier insufficient fix. |
| 3 | [Windows OpenCode test #38149560893](https://github.com/dougmcdonald87/dougs-box/actions/runs/38149560893) | Actual OpenCode Windows asset downloaded and launched; `--version` succeeded. |
| 4 | [Windows stages test #38150202692](https://github.com/dougmcdonald87/dougs-box/actions/runs/38150202692) | Existing Restic installer target `0.18.4` does not exist in upstream release history. New `0.19.1` ZIP checked against SHA256 and versioned executable renamed to restic.exe; real Windows install passed. RDP test exposed broken NetworkCredential expression before any user rerun. |
| 5 | [Windows stages test #38150260090](https://github.com/dougmcdonald87/dougs-box/actions/runs/38150260090) | Real RDP Windows configuration succeeded (runneradmin, NLA, TCP 3389), but custom firewall assertion had a false negative because Windows formats CIDR as netmask. |
| 6 | [Local Restic integration #38150544218](https://github.com/dougmcdonald87/dougs-box/actions/runs/38150544218) | Actual backup initialized, snapshot listed and canary round-trip SHA256 verified. Restoration failed because script requested non-existent `stats --mode archive-size`. |
| 7 | [Restic and RDP integration #38150605320](https://github.com/dougmcdonald87/dougs-box/actions/runs/38150605320) | After switching to valid `restore-size`, real isolated encrypted backup and recovery of intentionally removed `Projects` and `Workspace` test files PASSED. Real RDP firewall restricted to `100.64.0.0/255.192.0.0` (equivalent to /10) PASSED. One OpenCode test received HTTP 403 from anonymous GitHub API. |
| 8 | [Rate limit test #38150752393](https://github.com/dougmcdonald87/dougs-box/actions/runs/38150752393) | Fixed OpenCode release discovery to authenticate with the workflow's automatic GitHub token; actual Windows installation test PASSED. |
| 9 | [Session startup test #38150908390](https://github.com/dougmcdonald87/dougs-box/actions/runs/38150908390) | Real Windows service/RDP setup, mock tailnet status, actual session-manager health and heartbeat functions PASSED. Output confirms `SESSION STARTUP SMOKE` without claiming a live interactive session. |

## Falsification cards

### Claim A — Restic can be installed from the repo code on the tested runner
- Smallest falsifier: Official asset fails download, hash check or executable launch.
- Competing explanation: Download link exists but ZIP contains `restic_0.19.1_windows_amd64.exe` instead of expected `restic.exe`.
- Cheapest attack: Actual Windows runner executes `install-restic.ps1` and `restic.exe version`.
- Observation: Installed and executed real Restic 0.19.1. **Survived this attack.**

### Claim B — Verified backup really preserves working files
- Smallest falsifier: Snapshot canary matches but deleted project file cannot be recovered.
- Competing explanation: Original backup captured canary/HOT settings only, not real work.
- Cheapest attack: Create real files under disposable runner Projects and Workspace; perform actual Restic init, backup, recover canary, delete files, restore and check exact bytes.
- Observation: Original implementation lacked roots and restore had an unsupported stats mode; corrected implementation passed on Windows. **Survived local backend integration only.**

### Claim C — RDP setup stays on the temporary runner and does not expose all IPs
- Smallest falsifier: Windows RDP firewall permits Any/public IPv4, NLA disabled or no 3389 listener.
- Competing explanation: Native Windows firewall masks are shown as address/netmask rather than CIDR, fooling a superficial checker.
- Cheapest attack: Run actual `configure-rdp.ps1` on disposable Windows Server runner, enumerate enabled RDP firewall rules and compare canonical masks.
- Observation: TCP/UDP RDP Windows firewall rules restricted to `100.64.0.0/255.192.0.0`, listener active, NLA 1. **Survived this attack.** This does not prove an actual RDP login from Doug's iPhone.

## Unverified and potential blockers

- New GitHub runner -> **actual Lenovo** REST backend TCP 8000, authentication, first repository init and verified canary round-trip: **NOT tested** by isolated local-storage CI. Lenovo agent reported storage service ready and authenticated; cross-host connectivity has not yet been exercised.
- GitHub session-manager remains alive over an interactive Windows RDP session for hours: **NOT tested** by a short readiness smoke.
- First actual interactive RDP sign-in to the ephemeral GitHub Windows host from user's device: **NOT tested**.
- Auto-restoring snapshots above currently configured 3 GiB limit is intentionally refused; do not imply a 100 GiB project is automatically hydrated. The ~100+ GiB refers to temporary runner D: free, not automatic hydration size.
- Tailscale ACLs currently broad, not tightened. DevBox storage has its own HTTP basic auth; no tailnet policy or user device tagging was changed.

## Primary references

- Restic official releases: https://github.com/restic/restic/releases
- Restic Windows ZIP latest and pinned sha256 listed by Scoop: https://github.com/ScoopInstaller/Main/blob/master/bucket/restic.json
- Restic scripting / repository exit code 10: https://github.com/restic/restic/blob/master/doc/075_scripting.rst
- Restic stats legitimate mode `restore-size`: https://restic.readthedocs.io/en/stable/manual_rest.html
- Restic REST credentials via `RESTIC_REST_USERNAME` / `RESTIC_REST_PASSWORD`: https://restic.readthedocs.io/en/latest/075_scripting.html
- Microsoft Windows Set-LocalUser parameters: https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.localaccounts/set-localuser
- **Skill applied:** https://github.com/Lum1104/prove-me-wrong/blob/main/SKILL.md

## Outcome classification

- Original real GitHub DevBox: **FALSIFIED** as operational before code fixes.
- GitHub OIDC+Tailscale join: **SURVIVED live run 38148379792**.
- Windows Restic installation, isolated backup/restore and RDP setup: **SURVIVED relevant isolated tests**.
- Complete live Lenovo-backed RDP DevBox: **UNVERIFIED**, subject to a single post-validation live trial.
- End-to-end real network/tailnet connection to Lenovo Restic server, actual RDP login and hours-long session retention are still **UNVERIFIED**.

## Pass 10 — OpenCode version falsifier, not just installer success

- **Claim challenged:** The previous `opencode.exe --version` smoke proved Dotty's **OpenCode v2** requirement.
- **Smallest falsifier:** The executable runs but prints a v1 release.
- **Observation:** Windows smoke #38149560893 printed v1.19.0 even though all its assertions passed. Upstream GitHub `releases/latest` selected v1.19.0, while the upstream v2 tag and official v2 CLI npm package had already been published.
- **Fix:** Replace v1 GitHub release installer with official `npm install --prefix <ephemeral Tools> @opencode/cli@2.0.24`, extract native Windows `opencode.exe`, and require actual output `opencode v2.0.24`. No WSL and no new user credential.
- **Test:** [Windows GitHub CI #38151475128](https://github.com/dougmcdonald87/dougs-box/actions/runs/38151475128) Windows OpenCode job **PASS**; confirmed `Official OpenCode v2.0.24 installed` and `WINDOWS OPENCODE V2 INSTALL SMOKE: PASS`.
- **Verdict:** Previous "v2 installed" claim **FALSIFIED**; new specific v2 Windows installation **SURVIVED** the real test.
- **Residual risk:** Version compatibility of restored plugins/configurations, user account login and real long-running DevBox remain untested.

Primary source: https://opencode.ai/v2/docs (official CLI uses `@opencode/cli` with platform-native postinstall).
