# DevBox

A repeatable, zero-cost, GitHub-hosted Windows development and debugging
workstation. One Windows session at a time, via RDP over Tailscale, state-safe
against the platform's six-hour limit.

Standard public Windows Actions runner (4 vCPU / 16 GB) -
>=100 GiB runtime-probed workspace -
Tailscale as the only network-security layer -
**[restic](https://github.com/restic/restic)/rest-server persistence on your own
hardware** -
**[OpenCode](https://opencode.ai)** on the box -
manual, audited, honest.

## The laws that decide every code review

1. **Tailscale only.** No TLS stack, no reverse proxy, no second VPN, no
   rest-server auth middleware. Windows login and the restic password stay because
   their applications need them.
2. **Zero spend.** Standard public runner only. Cache at 10 GB. No paid storage or
   artifacts. Budgets set by hand in GitHub's UI.
3. **Never assume D:.** Probe every fixed writable volume, binary GiB, loud
   failure when nothing qualifies.
4. **Append-only storage.** The DevBox backs up; deletion vocabulary does not
   exist in this codebase. Retention is the owner's later manual move at the host.
5. **Never false READY.** A failing mandatory health check prints
   `DEVBOX FAILED` with the exact next action.

## Repository map

```text
.github/workflows/devbox.yml        session boot (manual)
.github/workflows/validate.yml      static gates per push
.github/workflows/probe-runners.yml capacity facts, manual
scripts/                            11 runner-side scripts
storage-host/                       7 storage-side scripts
config/                             *.example.json (no secrets, ever)
security/                           Tailscale grants fragment
tests/                              Pester 5 static-logic suite
docs/                               RESEARCH / ARCHITECTURE / OPERATING-MODES /
                                    STORAGE / BACKUP-RECOVERY / RDP-LICENSING-NOTE /
                                    TROUBLESHOOTING / ZERO-COST-CHECK / FIRST-RUN
```

## Save / Finish controls and optional iPhone launcher

For any **new** DevBox session started after deployment of this feature,
the Windows Public Desktop contains `Save DevBox State Now` and
`Finish DevBox Safely`. The latter requests and verifies a fresh Lenovo
Restic snapshot **before** the normal GitHub job voluntarily exits.
If verification fails, the requested stop is refused. GitHub timeouts and
unexpected cancellations remain outside this guarantee.

See [iPhone starter and verified-stop setup](docs/IPHONE_START_VERIFIED_STOP.md)
and the [adversarial evidence ledger](docs/CONTROL_ADVERSARIAL_EVIDENCE_2026-10-11.md)
for status, setup, residual risks and test links. A fully configured one-tap
iPhone Shortcut is **not** shipped or activated: the owner must set it up
and test it, with a repo-scoped GitHub token. No automatic six-hour relaunch.

## Fast start

Skim `docs/FIRST-RUN.md` for the one-time UI setup (13 numbered clicks) and the
every-session loop. Sessions run from the Actions tab; work happens after
`DEVBOX READY`, over RDP inside the tailnet; every important milestone calls
`Save DevBox State Now`; the day ends with `Finish DevBox Safely`, not Cancel.

## What to read next

| If you want... | Read |
|---|---|
| the why behind every phase | `docs/ARCHITECTURE.md` |
| where each fact came from | `docs/RESEARCH.md` + `docs/SOURCE-REGISTER.md` folded from the skill pack |
| cost accounting honesty | `docs/OPERATING-MODES.md` |
| storage and repository design | `docs/STORAGE.md` |
| recovery expectations | `docs/BACKUP-RECOVERY.md` |
| RDP legality boundaries | `docs/RDP-LICENSING-NOTE.md` |
| when something breaks | `docs/TROUBLESHOOTING.md` |

## Honest limits

No design guarantees: GitHub keeps D:, runner specs never change, Actions terms
never change, licensing wording never changes, or that a Cancel cannot outpace a
final save. This repo handles those facts by probing, by periodic snapshots, by
hard budgets, and by refusing to declare success that has not happened yet.
