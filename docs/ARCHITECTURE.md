# ARCHITECTURE.md

## The shape of the thing

```text
OWNER DEVICE (Doug)
    |
    | Tailscale (sole trust boundary)
    v
GITHUB WINDOWS DEVBOX (ephemeral, tagged)
    standard public runner, 4 vCPU/16 GB
    >=100 GiB runtime-probed workspace
    runneradmin RDP, NLA, OpenCode
    |
    | Tailscale only, plain HTTP, TCP 8000
    v
TRUSTED WINDOWS STORAGE PC (Doug's own hardware)
    rest-server --append-only --no-auth
    bound to the host's tailnet IPv4 only
    persistent restic repository
    optional SMB share for cold data
```

## Components and why

| Component | Purpose | Non-negotiable law it enforces |
|---|---|---|
| `.github/workflows/devbox.yml` | interactive session: boot DevBox | workflow_dispatch only; concurrency `devbox-session` |
| `.github/workflows/validate.yml` | static gates per push | YAML + PS parse + bookkeeping grep + secret scan |
| `.github/workflows/probe-runners.yml` | capacity facts, manual | never auto; feeds `DEVBOX_RUNNER_LABEL` |
| `scripts/bootstrap.ps1` | workspace structure + knobs | `>=100 GiB` check, `job timeout < 360` |
| `scripts/discover-storage.ps1` | volume selection | probes; never assumes D: |
| `scripts/configure-rdp.ps1` | one admin session | runneradmin preferred; NLA; no RDS roles |
| `scripts/install-opencode.ps1` | shared binary install | reuses current official v2 x64 asset |
| `scripts/connect-persistence.ps1` | restic over tailnet | repo URL from tag-resolved storage host |
| `scripts/restore-state.ps1` | HOT first, Git canonical | no destructive restore; caps auto-restore |
| `scripts/save-state.ps1` | snapshot + canary proof | exit codes hard; success needs listing + canary |
| `scripts/hydrate-data.ps1` | cold data on demand | disk-critical refusal |
| `scripts/session-manager.ps1` | heartbeat/deadline/saves | deadline < hard limit; cancel untouched |
| `scripts/health-check.ps1` | readiness gate | any failure = `DEVBOX FAILED` |
| `storage-host/*` | rest-server lifecycle on Doug PC | bind tailnet IP only; persistent path; boot task |
| `security/tailscale-grants.example.hujson` | ACL fragment | minimal ports; mergeable; no secrets |

## Data temperatures

HOT (auto-restore, small): OpenCode config, AGENTS.md, notes.
PROJECT: Git is canonical; snapshots overlay the rest.
COLD: datasets, media, archives; hydrate on demand.
DISPOSABLE: build dirs, dependency dirs; never backed up.

See `OPERATING-MODES.md` for the licensing/mode triangle and `BACKUP-RECOVERY.md`
for the recovery flow and the append-only consequences.
