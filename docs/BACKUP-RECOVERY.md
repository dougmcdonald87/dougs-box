# BACKUP-RECOVERY.md

## The append-only law

The DevBox backs up. The DevBox NEVER shrinks, trims, rewrites, or reinitialises
the repository. There is no deletion command anywhere in this repository's code,
by design and by audit. Recovery is proven by a round-trip canary restore with
hash comparison, not by an exit code.

## Backup cadence

- `save-state.ps1` runs on demand (shortcut) and periodically (every
  `backup_interval_minutes`, default 10) via `session-manager.ps1`.
- `--skip-if-unchanged` keeps silent sessions from producing empty snapshots.
- After a backup exits 0 the script fetches the snapshot listing and *verifies the
  new snapshot id exists before reporting success*. A green exit with no snapshot
  is treated as failure.

## Restore flow

1. `restore-state.ps1` fetches snapshot json. Empty history = first run = normal.
2. Restore happens into `Temp\restore-staging`, then targeted `Copy-Item -Force`
   over the HOT paths. NEVER a destructive overwrite mode.
3. `stats --mode archive-size` warns when the payload exceeds the
   auto-restore cap; heavy data stays remote until hydration.
4. `hydrate-data.ps1` pulls COLD patterns on demand, within disk budget, and
   refuses below the critical threshold.

## Recovery proof and limits

- Canary: `PersistentData\canary\DEVBOX-CANARY.txt` round-trips via restore into
  temp and hash compars; mismatch is a hard failure.
- GitHub Cancel can kill the session manager and the workflow before a final
  save completes. Periodic snapshots bound the loss window to
  `backup_interval_minutes` at most. Normal shutdown is the `Finish DevBox Safely`
  shortcut, which triggers one last `save-state.ps1` and then stops.
- The six-hour hard limit stops runners indefinitely in flight; the session
  manager's deadline is always below it with reserve for a final save.

## Owner's retention choice (explicitly off-DevBox)

Snapshot removal is a manual, one-time-owner-only operation on the storage host,
interactively, after an explicit review of what is in the repository. This
repository ships no such command; if you see one, audit it.
# Opt-in cloud E candidate

The normal manual DevBox launch still defaults to `home`. The candidate branch adds `persistence_backend` choices `github-release` and `migrate-to-github`. These use an owned E working-drive alias on the disposable runner; encrypted GitHub checkpoints provide persistence after that runner ends. An occupied E is refused. Existing D and source backups are retained.

First migration, after controlled integration of the tested opt-in code: manually run DevBox on `main` with operation `start` and persistence backend `migrate-to-github`. The existing Tailscale OIDC trust pins `devbox.yml@refs/heads/main`; a draft-branch launch is refused by the unchanged identity preflight. The existing source must be reachable once. Its verified snapshot is restored before a cloud repository is initialized or published. An empty/unverified source, an existing published cloud baseline, or failed publication refuses successful migration. Existing source metadata is retained on failure. Save/Finish thereafter require verified cloud receipts.

Subsequent candidate launch: choose `github-release`. Startup must fetch a matching production checkpoint, verify its encrypted data/receipt identities and restore the selected C/workspace/OpenCode state. It does not need the home storage endpoint. A missing/invalid checkpoint refuses empty startup.

The existing portable lifecycle client can send either explicit choice using its existing Actions-write credential: `python3 scripts/devbox_lifecycle.py start --backend migrate-to-github`, then `start --backend github-release` for the fresh recovery acceptance run. The normal `start` call retains its original main/home payload. No credential is embedded in the client or checkpoint.

Do not change the default, repurpose D or disconnect the existing source until Doug's actual saved data has passed a fresh cloud-only candidate restore. Current tests establish selected-path recovery, not full Windows/all-AppData/arbitrary installed-program compatibility. Transport caps remain 8GiB assembled,512MiB pieces and1MiB manifests; there is no unlimited free-storage guarantee.
