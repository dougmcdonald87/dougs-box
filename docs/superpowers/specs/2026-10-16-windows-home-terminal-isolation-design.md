# Windows 10 Home pilot — isolated terminal pairing on the guest-hosting runner
Date: 2026-10-16
Status: DESIGN / SECURITY GATE — not implemented, not approved for live launch
Repository: dougmcdonald87/dougs-box
Target branch: pilot/windows-home-connection-20261015
Protected original: main at 2ca7bd4ad2c07ce1162d86be84c1a94c9045da55

## User purpose and scope
Give the assistant a new Google-authorised Desktop Commander terminal on the **same disposable Windows GitHub Actions host** that restores and runs the Windows 10 Home Hyper-V VM. Allow owner Save / Finish through the existing first-party encrypted checkpoint publisher; ultimately prove a complete fresh-host restore. This is the Windows 10 pilot only. Never target a Lenovo, HP, other user's device, an expired runner registration, or the old main DevBox. No automatic chaining, no unapproved paid usage, no changes to the production backup channel, no plaintext credentials in handovers or logs.

## Verified baseline
The current `.github/workflows/windows-state-probe-validate.yml` has separate `operator` and `restore-hold` jobs. `operator` starts `.github/actions/pilot-device/index.mjs` with Desktop Commander, but has no Hyper-V guest restore. `restore-hold` restores and boots the guest, then starts `.github/actions/pilot-device/hold-operator.mjs`, the first-party Save/Finish worker, but not Desktop Commander. Run 38833814645 completed with zero owner requests processed and no verified Finish. Do not infer that user never submitted a request, or that the pairing was attempted.

The old `index.mjs` combines an external executable with privileged Save/Finish handling. Its `sandboxDeviceEnvironment` filters child environment variables, but **this is NOT a Windows security boundary**: a third-party process under the same Windows identity as a secret-bearing worker may inspect accessible processes/files. The current first-party hold explicitly says `NO third-party remote agent here`. Reusing it as-is in the privileged hold would weaken secret isolation.

## Design: host identity + least-privilege terminal sidecar
1. After preflight OIDC, isolated Tailscale admission, immutable guest restore, `PilotOwner` login verification and desktop shortcuts, create an ephemeral *unprivileged* local Windows OS account dedicated to Desktop Commander on **that same host**. This SID must not be in Administrators, Hyper-V Administrators, local RDP operator accounts or the ACL granting access to `ProgramData\\WindowsHomePilot\\<run_id>`.
2. Keep the first-party `hold-operator.mjs` running in the original privileged runner context with the existing `GH_TOKEN` and `RESTIC_PASSWORD`. The third-party Desktop Commander must instead run as the separate low-privilege Windows account with a new isolated profile, minimal allowlisted environment, and no privileged process handles, secret-bearing files or publication credentials. Launch must fail closed if Windows logon and token/ACL verification fail.
3. Supervise both processes within the **same GitHub Actions job** (not another GitHub machine). The first-party supervisor must capture Desktop Commander's device-code readiness, encrypt the pairing payload with the existing pinned RSA public modulus, upload with `@actions/artifact` with short retention, and expose only artifact identity and readiness in logs. The owner completes the provider's Google sign-in/authorisation. Never print pairing codes, credentials or tokens.
4. On terminal connection, verify the **current GitHub run ID and the target SID** with a harmless read-only identity command before other activity. A connection to any previously registered runner, to an arbitrary machine, or to any personal computer is forbidden, even if it has the same display name.
5. Keep privileged Save/Finish operations mediated only by `hold-operator.mjs` using signed/scoped request metadata and owner-facing shortcuts. The remote terminal must never directly invoke the checkpoint publisher or read control-dir requests/responses. If diagnostic visibility is necessary, add a narrow audited first-party read-only status endpoint rather than granting operator/admin access to the remote account.
6. Terminate the agent/account at the end of the bounded pilot job. Never persist connection sessions into a checkpoint. Do not launch a duplicate old/new runner automatically.

## Prove Me Wrong attack
Claim: child environment filtering by itself keeps backup credentials confidential.
Smallest falsifier: a same-user child can inspect a secret-bearing parent process or readable control material even though its own environment has no `RESTIC_PASSWORD`.
Competitor: only a distinct Windows security identity with verified ACL/token boundaries provides effective local separation.
Cheapest safe test: on a **disposable pilot Windows runner**, create a fake sentinel credential in a separate protected first-party context and verify the agent's actual low-privilege token cannot read it or protected control directories; record outcome without printing the sentinel. A static allowlist test alone is inconclusive. No real secrets or production state in the test.

## Acceptance gates (in order)
- A. Test RED then GREEN: workflow is pilot-only, primary guest restore precedes pairing, privileged first-party Save/Finish worker retained, paired agent runs with distinct unprivileged SID, no duplicate runner job or original `devbox.yml` invocation.
- B. Native Windows sentinel denial test from the agent OS identity; wrong SID, missing password/profile, or inaccessible Desktop Commander binary fails closed. Secret value never logged.
- C. Pairing readiness and owner Google approval verified on a single authorised pilot run; current run ID matches both host and Desktop Commander endpoint; actual Windows 10 guest remains booted.
- D. Owner desktop Save then Finish produce authenticated immutable generation receipts, not just request-submitted messages; an interrupted producer does not destroy the seed.
- E. Manually launch a genuinely different pilot runner with exact generation/source SHA; prove VM GUID, program, document hash, Windows/app preferences and iPhone guest GUI reconnect. No bare green status claim substitutes for proof.
- F. Check `main` head and production checkpoint release channel unchanged. Update handover ZIP with steps, failed attacks, result links, and exact status.

## Deliberate exclusions
Do not solve guest internet/audio until terminal + persistence gates are proven. Do not merge pilot work into main. Do not equate host RDP with guest GUI. No new permanent accounts, public RDP, external cloud spending or broad Tailscale grants.

## Implementation readiness
This is a revised design prompted by a security counterexample during the approved workflow-integration task. Code changes and expensive live launches remain gated on a native OS-isolation feasibility check. Static repository inspection verifies the mismatched jobs; **OS-level isolation, device Google sign-in and Save/Finish have not been runtime-verified**.