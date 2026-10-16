# TROUBLESHOOTING.md

Every entry names the symptom, the most likely cause, and the exact next action.

## Workspace

- `DEVBOX FAILED: NO >=100 GiB WORKSPACE`: no local volume with >=100 GiB free.
  Next action: enable network fallback only if the storage share qualifies, else
  abort as the correct outcome.
- Disk warnings below 25 GiB free / critical below 10 GiB: session-manager warns;
  hydration suspends at critical. Disposable dirs (`node_modules`, `.venv`,
  `target`, `bin`, `obj`, workspace `Temp`) rebuild; never a user-datasheet wipe.

## Tailscale

- run never joins: check the `devbox` Environment secrets `TS_OAUTH_CLIENT_ID`
  and `TS_AUDIENCE`; verify the WIF trust in the Tailscale console points at this
  repo and workflow; the step log names the failing claim exactly.
- Storage host unreachable on 8000: confirm the Grant's fragment was merged;
  confirm the storage host is online; `tailscale ping <storage-ip>` from the
  DevBox node answers direct vs relayed (DERP). Relayed is NOT a blocker for RDP;
  it only warns against bulk hydration.

## RDP

- Connection refused: health-check the runner inside Actions; prefer seeing the
  `3389 listening` line in the run log. If absent: TermService or firewall kept it
  off; re-run configure-rdp and watch the step.
- Password rejected: `DEVBOX_RDP_PASSWORD` exists in the Environment, not as a
  repo secret; check the approval supplied; reconnect.
- runneradmin unexpectedly disabled mid-session: fallback path continues with a
  purpose-made devbox account; tools live on the shared `Tools` path so the new
  session sees them too.

## Persistence / restic

- `rest-server` unreachable: `storage-host/check-storage-host.ps1` locally on the
  storage box; if it fails, setup-storage-host.ps1 again and inspect task history.
- Restic password rejected: `RESTIC_PASSWORD` changed between sessions is the
  giveaway; the repository is encrypted as a unit - use the same secret or you
  need a new repository. The DevBox never re-initialises one that exists.
- Slow backups: check tailscale relay path; `tailscale status --json` shows a
  DERP relay when NAT traversal fails; relayed path is fine for small periodic
  saves and poor for bulk hydration - that is the design remedy.

## OpenCode

- Not found from RDP: `install-opencode.ps1` writes to the shared Tools path and
  updates machine PATH; log out of the RDP session and back in to refresh PATH.
- Version mismatch: install script re-uses an existing binary; delete the folder
  in the shared path, re-run install.

## Workflows

- Job queuing forever: `DEVBOX_RUNNER_LABEL` var must exist and match one of the
  allowlist entries; probe-runners verifies labels still exist upstream.
- Session died early: memory - the session-manager's `last-error.txt` records the
  exact FAIL line; restore from the last snapshot thumbnail and start again.
