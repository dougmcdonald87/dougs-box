# Machine and workload identity: never confuse these

| Role | Selector | What it is | Never infer |
|---|---|---|---|
| Original DevBox | Repo dougmcdonald87/dougs-box, main, workflow .github/workflows/devbox.yml | Existing production-like remote development workflow with Lenovo-backed restic | That pilot changes are on main |
| Pilot DevBox source | Same repo, branch pilot/windows-home-connection-20261015, workflow .github/workflows/windows-state-probe-validate.yml | Isolated Windows Home persistence/connection experiment | That branch SHA identifies a running machine |
| Outer host | GitHub Actions run ID, job ID, host UUID, commit SHA | Ephemeral Windows runner executing pilot | That it is the guest or survives job termination |
| Windows 10 Home guest | Hyper-V VM GUID/name, guest OS identity, accepted encrypted generation | Windows system whose state must survive fresh outer-host restoration | That outer-host RDP proves guest GUI works |
| Personal machines | Current Desktop Commander device list, user-confirmed role, live hostname | Local HP/Lenovo machines, may host old backups | That an offline or duplicate label is safe to target |

## Registered local devices
As of 2026-10-18, Desktop Commander listed two personal Windows desktop registrations and four historical cloud-runner registrations; all six were offline. This public kit deliberately does not publish personal hostnames, device UUIDs or addresses. Fetch them from the authenticated device list on every session. A duplicate runner label can represent multiple distinct device IDs.

## Identity card required before write
- Purpose/role: original | pilot | outer-host | guest | personal
- GitHub: repository, branch, HEAD SHA, workflow, run ID, job ID, status
- Desktop Commander: current device ID, online flag, ping, hostname/OS (if available)
- Guest: VM GUID, source generation, guest identity, observed boot state
- Owner authorization: exact operation and scope
- Unknowns: explicit UNKNOWN, never silently inferred

## Read-only commands for authenticated Windows target
    hostname
    $env:COMPUTERNAME
    Get-CimInstance Win32_ComputerSystemProduct | Select-Object UUID
    git remote -v
    git branch --show-current
    git rev-parse HEAD
Do not assume git is installed or that the machine contains the expected checkout. Never use a hostname alone as proof of authorization.
