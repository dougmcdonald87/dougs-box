# DevBox safety and functional audit — 2026-10-11

Status: **DO NOT LAUNCH DEVBOX**. This is an evidence ledger, not a green-light certificate.
Branch: `safety/devbox-non-disruptive-fixes-20261011`. This branch is deliberately separate from `main`.
No changes to user devices, Tailscale policy, RustDesk, OpenCode servers, Llama control page, or shared Z: drive were made.

## Non-disruption boundary

- Existing user-owned Lenovo storage host: `desktop-60q2ks9`, current Tailscale IPv4 `100.70.202.110`. Do not retag or reauthenticate.
- HP: `desktop-9kmm43p`; iPhone: `iphone-15-pro-max`. Keep all current services and existing file sharing.
- Both computers have online-accessible OpenCode services. Exact port allocation is not asserted here.
- RustDesk is an independent recovery path on the two computers and is out of scope.
- Existing tailnet HuJSON: a broad `src:["*"], dst:["*"], ip:["*"]` grant with SSH, Funnel and two tag-owner declarations. Do not replace it without tests and explicit approval.

## Corrections committed on this branch (not deployed)

1. `.github/workflows/devbox.yml`: Tailscale WIF/OIDC action corrected from `oauth-secret: TS_AUDIENCE` to `audience: TS_AUDIENCE` (Tailscale docs: https://tailscale.com/docs/integrations/github/github-action).
2. `scripts/connect-persistence.ps1`: discovers the existing user-owned Lenovo through an explicitly supplied tailnet IPv4, rather than requiring it to adopt `tag:devbox-storage`. Does not modify tailnet device identity. Propagates non-secret restic executable path across steps.
3. `.github/workflows/devbox.yml`: supplies current Lenovo tailnet IP to the persistence-discovery step. Recheck the IP against the device list before any run; it is not a permanent DNS identity.
4. `scripts/bootstrap.ps1`: writes non-secret workspace environment settings to the `GITHUB_ENV` file because each Actions run step starts a fresh process. Also sets DEVBOX_TEMP.

## Unresolved blocking defects (source-inspected; **not** runtime-tested)

- `scripts/restore-state.ps1` is called before `scripts/save-state.ps1 -First` initializes the restic repository. On an empty storage host, snapshots listing can fail; the recovery path is not proven.
- `scripts/save-state.ps1` constructs restic arguments but never includes the `backup` subcommand. Its current result handling conflates exit codes and command output, and the canary directory is not included among `backupRoots`. Its claimed backup-and-restore proof is not reliable as implemented.
- `scripts/session-manager.ps1` loops inline for the duration of the session, but the workflow's health check and READY summary follow that step: they may never execute while the user can still access the runner. Conversely, if the workflow finishes, the ephemeral Tailscale node is removed. The lifecycle requires redesign and live proof.
- `scripts/health-check.ps1` requires `heartbeat.json`, but the reviewed session manager code does not write that file.
- `storage-host/setup-storage-host.ps1` launches an unauthenticated append-only rest-server on a live machine. Binding to a tailnet IPv4 is not sufficient isolation while the current all-to-all tailnet grant remains active.
- The repository's static "green" tests are not evidence of functioning persistence, RDP, a long-lived runner, or continuous server availability.
- Whether current GitHub Actions usage and desired remote-interactive Windows use comply with the provider's present terms and the owner's strict zero-spend condition needs review before starting a job.

## Safe next sequence

1. Repair first-run repository init, restic backup/canary verification, process lifecycle and heartbeat on this branch; produce focused tests that fail on old code and pass on new code.
2. Prepare candidate minimal tailnet policy + explicit acceptance/denial tests of all three existing devices, OpenCode access, Z: sharing, AI control page, and DevBox 3389/storage 8000. Do not change live tailnet policy to test an idea.
3. Dry-run static checks without touching laptops and inspect diffs. Never declare live success from static inspection alone.
4. Request explicit user approval before **any** change to tailnet policy or Lenovo storage PC. Preserve a tested rollback and a separate RustDesk access route.
5. Run one controlled integration test only once costs, Tailscale rights, file sharing, storage protection, and RDP feasibility are verified.

## References

- Official Tailscale GitHub Action: https://tailscale.com/docs/integrations/github/github-action
- Official policy syntax and access tests: https://tailscale.com/docs/reference/syntax/policy-file
- Official Tailscale grants: https://tailscale.com/docs/reference/syntax/grants
- Source branch: https://github.com/dougmcdonald87/dougs-box/tree/safety/devbox-non-disruptive-fixes-20261011


## Critical feasibility challenge — FREE Windows runner workspace

**Finding:** official GitHub runner documentation lists standard public Windows x64 runner as
**4 vCPU, 16 GB RAM, 14 GB SSD**. The DevBox design requires a 100 GiB *local fixed writable workspace*.

- Narrow claim challenged: "The free standard public Windows runner reliably offers >=100 GiB locally usable fixed storage."
- Strongest source against claim: https://docs.github.com/en/actions/reference/runners/github-hosted-runners (Windows row, 14 GB SSD).
- Secondary evidence: GitHub removed accessible D: for public windows-2025 in July 2025:
  https://github.com/actions/runner-images/issues/12416
- Smallest falsifier/competitor: a real \`probe-runners.yml\` manual run could reveal a qualifying accessible >100 GiB fixed volume despite the current published standard specification.
- Status: **Official published specifications contradict the design; no live probe has been run by this assistant.**
- Risk implication: do NOT treat "100+ GiB free standard runner" as a known fact and do NOT spend money on larger runner upgrades.
- Safe owner action: GitHub > dougmcdonald87/dougs-box > Actions > Probe runners > Run workflow on main, read reported disk table. The workflow only does runner introspection and reads repository code; it does NOT request Tailscale secrets or contact Lenovo/HP. The publicly hosted probe itself is subject to GitHub's normal policies and availability.
- Next decision: If no >=100 GiB fixed writable volume qualifies, **stop the local-workspace design** and revisit workspace/storage requirements; do not claim zero-cost 100 GiB is solved.

## Additional source-level repairs on the isolated branch

- \`scripts/configure-rdp.ps1\` and \`scripts/health-check.ps1\`: set/check \`UserAuthentication=1\`, the documented Microsoft value for required NLA. Source: https://learn.microsoft.com/en-us/windows-hardware/customize/desktop/unattend/microsoft-windows-terminalservices-rdp-winstationextensions-userauthentication
- \`scripts/save-state.ps1\`: actual \`restic backup\` command, require \`summary.snapshot_id\`, include the canary directory, list the snapshot, restore and checksum the canary. Upstream docs: https://restic.readthedocs.io/en/stable/075_scripting.html
- \`scripts/restore-state.ps1\`: first-run uninitialized repository code 10 is recognized rather than treated as a fatal restoration failure. **Existing-snapshot restore path remains untested and still needs review**.
- \`scripts/session-manager.ps1\` and \`.github/workflows/devbox.yml\`: session manager is now the final, blocking workflow step; writes heartbeat and performs health check before reporting READY; periodic saves get the environment-only Restic password.

**Proof status:** All the above modifications are committed in the *safety branch*, but source code was not executed under GitHub/PowerShell/Restic/Tailscale. Static checks and source review are not equivalent to a passing live backup, RDP, or working environment. Additional latent bugs may exist. No tailnet policy or laptop services modified.
