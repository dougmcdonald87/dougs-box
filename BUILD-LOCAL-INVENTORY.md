# BUILD-LOCAL-INVENTORY

Ledger of every file created on THIS system (doug HP laptop) for the DevBox build,
from this point forward. Purpose: after the build, Doug and I assess and clean
appropriately (Doug's instruction, 2026-10-10).

Rules:
- Log EVERY file created on this laptop for this build - inside or outside the build root.
- Fields: path | purpose | size | time (UTC) | keep candidate / disposable.
- "keep candidate" is provisional. Disposal is the owner's call, never mine alone.
- GitHub-side artefacts (workflow runs, secrets, repo state) are OUT of scope: not on this system.

## Baseline (created this entry)

| Path | Purpose | Size | Time (UTC) | Keep candidate |
|---|---|---|---|---|
| `C:\Users\dougm\repos\devbox\` | Build staging root for the future DevBox repo (pre-git) | - | 2026-10-10 | Assess after build |
| `C:\Users\dougm\repos\devbox\BUILD-LOCAL-INVENTORY.md` | This ledger | - | 2026-10-10 | Keep |

## Local-tooling probe result (no files created; facts for the build)

- Python 3.12.10 present; **pyyaml missing** -> needed for YAML validation (pip install pyyaml).
- Windows PowerShell 5.1 present (AST parse/`[System.Management.Automation.Language.Parser]` works on any PS).
- Pester **3.4.0** installed (ancient); the V3 spec's Pester 5 tests cannot run under it -> verify tests statically now, run them later under Pester 5 (install via PowerShellGet) or mark LIVE TEST REQUIRED.
- PSScriptAnalyzer **not installed** -> static lint optional locally (install check pending) or defer to validate.yml on runner.
- Git 2.55.0 present; pwsh 7 absent; C: free 10.4 GB (floor 9 GB, watch it).
- Node v24.19.0 present (node/npx side available if needed for any local helper).

## Files created (append below as they are made, newest last)

### DevBox repo build pass (2026-10-10, build turn)

| Path | Purpose | Keep candidate |
|---|---|---|
| `C:\Users\dougm\repos\devbox\.gitignore` | secret/out artefact guard | Keep |
| `C:\Users\dougm\repos\devbox\config\devbox.example.json` | knob template (no secrets) | Keep |
| `C:\Users\dougm\repos\devbox\config\persistence.example.json` | rest-server config template | Keep |
| `C:\Users\dougm\repos\devbox\security\tailscale-grants.example.hujson` | mergeable grants fragment | Keep |
| `C:\Users\dougm\repos\devbox\.github\workflows\devbox.yml` | session workflow (manual, env devbox) | Keep |
| `C:\Users\dougm\repos\devbox\.github\workflows\validate.yml` | static gates per push | Keep |
| `C:\Users\dougm\repos\devbox\.github\workflows\probe-runners.yml` | capacity probe (manual) | Keep |
| `C:\Users\dougm\repos\devbox\scripts\common.ps1` | shared helpers + $OneGiB | Keep |
| `C:\Users\dougm\repos\devbox\scripts\bootstrap.ps1` | workspace tree + inventory | Keep |
| `C:\Users\dougm\repos\devbox\scripts\discover-storage.ps1` | volume probe/write-test | Keep |
| `C:\Users\dougm\repos\devbox\scripts\configure-rdp.ps1` | RDP + NLA + runneradmin | Keep |
| `C:\Users\dougm\repos\devbox\scripts\install-opencode.ps1` | official v2 binary install | Keep |
| `C:\Users\dougm\repos\devbox\scripts\connect-persistence.ps1` | tailnet tag resolve + restic | Keep |
| `C:\Users\dougm\repos\devbox\scripts\restore-state.ps1` | HOT restore, staging copy | Keep |
| `C:\Users\dougm\repos\devbox\scripts\save-state.ps1` | snapshot + canary proof | Keep |
| `C:\Users\dougm\repos\devbox\scripts\hydrate-data.ps1` | cold data on demand | Keep |
| `C:\Users\dougm\repos\devbox\scripts\session-manager.ps1` | heartbeat/deadline/saves | Keep |
| `C:\Users\dougm\repos\devbox\scripts\health-check.ps1` | READY gate | Keep |
| `C:\Users\dougm\repos\devbox\storage-host\setup-storage-host.ps1` | rest-server + boot task | Keep |
| `C:\Users\dougm\repos\devbox\storage-host\start-rest-server.ps1` | start helper | Keep |
| `C:\Users\dougm\repos\devbox\storage-host\stop-rest-server.ps1` | stop helper | Keep |
| `C:\Users\dougm\repos\devbox\storage-host\check-storage-host.ps1` | health verifier | Keep |
| `C:\Users\dougm\repos\devbox\storage-host\maintenance.ps1` | inspection/dry-run | Keep |
| `C:\Users\dougm\repos\devbox\storage-host\remove-storage-host.ps1` | teardown (data preserved) | Keep |
| `C:\Users\dougm\repos\devbox\storage-host\setup-smb-cold-storage.ps1` | optional SMB share | Keep |
| `C:\Users\dougm\repos\devbox\tests\devbox.tests.ps1` | Pester static-logic suite | Keep |
| `C:\Users\dougm\repos\devbox\docs\RESEARCH.md` | freshness gates + candidate values | Keep |
| `C:\Users\dougm\repos\devbox\docs\ARCHITECTURE.md` | component map + laws | Keep |
| `C:\Users\dougm\repos\devbox\docs\OPERATING-MODES.md` | OSS/Personal/Commercial truth | Keep |
| `C:\Users\dougm\repos\devbox\docs\STORAGE.md` | workspace + repo layout | Keep |
| `C:\Users\dougm\repos\devbox\docs\BACKUP-RECOVERY.md` | append-only semantics | Keep |
| `C:\Users\dougm\repos\devbox\docs\RDP-LICENSING-NOTE.md` | admin-session boundary | Keep |
| `C:\Users\dougm\repos\devbox\docs\ZERO-COST-CHECK.md` | hard £0 rules | Keep |
| `C:\Users\dougm\repos\devbox\docs\TROUBLESHOOTING.md` | symptom->cause->action | Keep |
| `C:\Users\dougm\repos\devbox\docs\FIRST-RUN.md` | one-time setup steps | Keep |
| `C:\Users\dougm\repos\devbox\SECURITY.md` | trust boundary + secrets map | Keep |
| `C:\Users\dougm\repos\devbox\README.md` | the front door | Keep |
| `C:\Users\dougm\repos\devbox\audit-build.py` | my local audit gate (7 scans) | Keep (tool, not repo content) |
| `C:\Users\dougm\repos\devbox\static-parse-all.ps1` | my local PS 5.1 AST gate | Keep (tool) |
| `C:\Users\dougm\repos\devbox\fix-parse-gate.py` | one-shot mechanical repair (already applied) | Disposable after re-audit |

### Side effects outside the repo (not DevBox content)

| Path | Purpose | Keep candidate |
|---|---|---|
| `C:\Users\dougm\AppData\Local\Temp\opencode\send-devbox-steps.ps1` | one-shot house-standard email (next-steps to dougmoug@gmail.com, 11 Oct 10:36) | Disposable |
| `C:\Users\dougm\repos\agent-skills-hub\skills\ai-antislop\references\pattern-log.md` (append) | Law-11 catch log of pause-response violation | Keep |
| pip-installed `pyyaml` into system Python 3.12 | enables YAML gate | Disposable re-install |
