# RESEARCH.md

## Research status

Static research pass from the V3 dossier on 2026-10-10 (source pack embedded in
the skill's `references/research-v3.md` and `source-register.md`). Runner facts,
licensing boundaries, Tailscale WIF mechanics, rest-server flags, and OpenCode v2
Windows routes all carry their citations over from that dossier.

## Freshness duty (V3 Phase 1)

Every platform claim here is a *candidate* until re-verified against current
first-party docs on the day of a real run. The following are the live-check gates:

1. GitHub public/private Windows runner specs and labels.
2. Hosted-job execution maximum and cancellation behaviour.
3. Windows Server 2025 image tools list and the state of D: (a ~140-147 GB free
   drive has been observed; only 14 GB is formally documented; probing stays law).
4. Tailscale GitHub Action inputs (current version pinned in devbox.yml).
5. restic + rest-server current stable versions and flags.
6. OpenCode v2 current Windows install path and asset naming.
7. Microsoft administrative RDP session limits.

## Recorded candidate values (bump after live verification)

| Value | Candidate | Where used |
|---|---|---|
| pinned checkout action | `actions/checkout` v5 commit `fbc6f3992d24b796d5a048ff273f7fcc4a7b6c09` | all three workflows |
| pinned tailscale action | `tailscale/github-action` v4.2.0 commit `d1b6cd204f8dceda5b3eaad7f1f767be390056cd` | devbox.yml |
| restic client | 0.18.4 | connect-persistence.ps1 |
| rest-server install | latest release API (never pinned by hand) | setup-storage-host.ps1 |
| runner label variable | `DEVBOX_RUNNER_LABEL` allowlist: `windows-2022`, `windows-2025`, `windows-2025-vs2026` | preflight job |

If any current source contradicts these, use the *current safe documented behaviour*
and record the difference here. Never improvise around a platform restriction silently.
