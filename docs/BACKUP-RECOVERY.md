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
