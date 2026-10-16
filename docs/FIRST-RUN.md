# FIRST-RUN.md

## One-time setup (README steps mirrored here with exact UI paths)

1. Choose your mode: see `docs/OPERATING-MODES.md`.
2. Create the repository, push this code to `main`.
3. Set the hard zero: Settings > Plans, then Billing > Budgets: Actions 0,
   Cache Storage 0, Stop usage; Billing > Alerts: on.
4. Leave the Actions cache bound at 10 GB.
5. Settings > Secrets and variables > Actions: create the variable
   `DEVBOX_RUNNER_LABEL` after running `probe-runners.yml` once.
6. Actions tab: run `probe-runners.yml`; read the log; note qualifying volumes.
7. Settings > Environments > create `devbox`; restrict to `main`.
8. Add secrets into the devbox environment:
   `DEVBOX_RDP_PASSWORD`, `RESTIC_PASSWORD`,
   `TS_OAUTH_CLIENT_ID`, `TS_AUDIENCE`
   (and SMB trio `STATE_SHARE_UNC`, `STATE_SHARE_USERNAME`, `STATE_SHARE_PASSWORD`
   only if you enabled SMB).
9. Enable Workflow Execution Protection in Actions Settings for devbox.yml
   (trusted actor only).
10. Tailnet admin: create `tag:github-devbox` and `tag:devbox-storage` tag owners
    then merge `security/tailscale-grants.example.hujson` into the Access Controls
    grants file at console.tailscale.com, removing `tcp://445` unless SMB is on.
11. On the storage PC: install Tailscale, tag the device `tag:devbox-storage`
    in the admin console, then run from a checkout of this repo:
    `pwsh -File storage-host/setup-storage-host.ps1`
    (then the optional `setup-smb-cold-storage.ps1` when wanted).
12. Actions tab: run `DevBox` (workflow_dispatch); approve the Environment when
    asked.
13. Wait for `DEVBOX READY`; open Tailscale; select the ephemeral node; RDP with
    `runneradmin`; work; `Save DevBox State Now` on milestones;
    `Finish DevBox Safely` when done.

## Every session (fast loop)

Actions > DevBox > Run workflow > approve > wait READY > Tailscale > RDP >
work > save > Finish Safely. **Cancel is emergency only** - periodic snapshots
bound the loss window, but a Cancel can still kill a final save in flight.
