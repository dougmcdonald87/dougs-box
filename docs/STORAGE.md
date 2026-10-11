# STORAGE.md

## Local fast workspace

- Every session probes every fixed writable volume.
- A volume qualifies at >=100 GiB *free* (binary GiB: 107,374,182,400 bytes).
- Preference: non-system drive, then most free.
- D: is observed on recent images at ~140-147 GiB free but is NOT formal. If no
  local volume qualifies, the session offers the explicit network fallback only
  when `allow_network_workspace_fallback: true`, else it fails loudly.

## Network fallback

- Only from `tag:github-devbox` to the storage host, TCP 8000 and (if SMB enabled)
  TCP 445 over the tailnet.
- Explicitly labelled in the log as `NETWORK WORKSPACE MODE` when in use.
- Slower; keep bulk hydration paused; periodic small backups continue.

## Storage host responsibilities

- rest-server bound to the host's tailnet IPv4 ONLY on TCP 8000.
- `--append-only --no-auth` arguments visible on the boot task; no TLS stack.
- Persistent data path (never `%TEMP%`).
- Scheduled Task `DevBox-RestServer` starts it at boot.
- Never place the DevBox repository on a one-off user session's temporary profile.

## Backup repository layout

`rest:http://<storage-tailscale-ip>:8000/devbox/`

Repository initialised exactly once. `persistence.json` (DevBox side, gitignored)
and `storage-host-state.json` (host side) record the same coordinates.

## Growth

Append-only means the repository only grows. Free-space drops are a maintenance
topic the owner runs at the storage host by hand (`maintenance.ps1` prints the
facts; the DevBox-side scripts are forbidden from touching removal commands).
