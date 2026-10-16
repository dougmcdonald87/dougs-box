# DevBox control rollout — adversarial evidence ledger (2026-10-11)

## Scope and immutable baseline
- Source repository: https://github.com/dougmcdonald87/dougs-box
- Candidate PR: https://github.com/dougmcdonald87/dougs-box/pull/6
- Tested head commit: `bfe85cd98e3989394907b2b13ca19db30ff2e1f3`
- Green CI run: https://github.com/dougmcdonald87/dougs-box/actions/runs/38168689355
- Separate, still-live original DevBox at observation time: https://github.com/dougmcdonald87/dougs-box/actions/runs/38152103213 (head `cb02e0e1fae63cb2c6f50352ed8488ef9396ff90`).
- No changes to Lenovo/HP Tailscale devices, policies, RustDesk or existing storage backend. No call to GitHub workflow dispatch, cancellation, or merging was made during CI development.

## Rule 1 — claim and falsifier

**Claim:** When the RDP user requests `Finish DevBox Safely`, the runner will not voluntarily stop until a *new* verified Restic snapshot is recorded.

**Smallest falsifier:** Stop returns true with a failed save or an unchanged stale `last-backup.json`.

**Strongest competitor:** A green backup return or existing snapshot record can be stale and wrongly authorize shutdown.

**Cheapest safe attack:** Inject failure, stale metadata, success, malformed request, duplicate request and thrown exception into the same queue function on a disposable runner; then invoke real Windows Restic with an isolated local repository.

## Evidence passes — actual observations (not hypothetical)

| Pass | Actual test | Observed outcome | Classification |
|---|---|---|---|
| 1 | Fake backup returns false on stop | Stop refused; negative result | **Survived** |
| 2 | Backup callback returns true but metadata unchanged | Stop refused; stale proof rejected | **Survived** |
| 3 | Backup callback writes fresh snapshot ID and UTC | Stop approved and result contains ID | **Survived** |
| 4 | Save-only command with fresh proof | Save acknowledged; stop false | **Survived** |
| 5 | Invalid control filename carrying text resembling code | Ignored; callback not invoked | **Survived** |
| 6 | Queue called again after completed command removed | No duplicate execution | **Survived** |
| 7 | Backup callback throws simulated storage outage | Stop refused; failure recorded | **Survived** |
| 8 | Disposable Windows Server `.lnk` creation and inspection | Both Save and Finish links existed and targeted request-control.ps1 | **Survived Windows smoke** |
| 9 | Real Windows Restic encrypted backup + canary SHA256 round-trip + project/workspace deletion and recovery | Snapshot and restored working files verified | **Survived isolated integration** |
| 10 | Real Restic script used as Stop queue callback in same isolated Windows job | New snapshot verified; Stop returned true and correct ID | **Survived isolated integration** |
| 11 | Existing Windows OpenCode v2 installer regression | OpenCode version gate still passed | **Survived regression** |
| 12 | Existing Windows RDP/firewall/health test | Completed successfully | **Survived regression** |

### Direct test receipts
- Control queue tests: https://github.com/dougmcdonald87/dougs-box/actions/runs/38168689355/job/114556509399 — log line `DEVBOX CONTROL ADVERSARIAL TESTS: 7 PASS`.
- Real Windows desktop shortcut smoke: https://github.com/dougmcdonald87/dougs-box/actions/runs/38168689355/job/114556509627 — log line `WINDOWS DESKTOP CONTROL SMOKE: PASS`.
- Real Restic backup, restore, Stop integration: https://github.com/dougmcdonald87/dougs-box/actions/runs/38168689355/job/114556509630 — log lines `WINDOWS RESTIC BACKUP AND REAL WORK RECOVERY: PASS` and `WINDOWS REAL RESTIC -> SAFE STOP INTEGRATION: PASS`.
- OpenCode Windows version: https://github.com/dougmcdonald87/dougs-box/actions/runs/38168689355/job/114556509685.
- Windows RDP: https://github.com/dougmcdonald87/dougs-box/actions/runs/38168689355/job/114556509691.

## Residual risks — not proven or still outstanding

1. **Real cross-host round-trip:** The new desktop stop UI has **not** been double-clicked through the user's iPhone RDP session and confirmed against Lenovo's live rest-server. Tests used a disposable local Restic repository, not Lenovo. Classify **UNVERIFIED**.
2. **Unexpected termination:** GitHub job timeouts and cancellations can bypass a final backup. The existing periodic snapshots reduce, not eliminate, work loss. Classify **UNMITIGATED platform risk**.
3. **iPhone starter:** Apple Shortcuts instructions use official GitHub `workflow_dispatch` REST API; no token was provisioned, no Shortcut installed on the phone, no API POST executed. Classify **UNVERIFIED**.
4. **Duplicate dispatch:** Existing `concurrency.cancel-in-progress: true` can cancel a live DevBox. The documented iPhone preflight is non-atomic and cannot guarantee avoidance. Classify **KNOWN RISK**. Do not represent startup as bulletproof.
5. **Compliance:** GitHub Actions product terms restrict unrelated hosted-runner work and disallow using hosted runners as general unrelated compute. User's concrete operating mode must be evaluated before the iPhone trigger is enabled.
6. **Desktop visibility:** Windows CI tested shortcut files and targets, not visibility on a signed-in RDP desktop. Classify **UNVERIFIED**.
7. **Timeout/slow backup:** The interactive client waits five minutes for a response, then reports unconfirmed. A longer-running backup could still complete later. Classify **KNOWN UX LIMIT**.

## Official sources
- Github workflow dispatch API: https://docs.github.com/en/rest/actions/workflows?apiVersion=2022-11-28#create-a-workflow-dispatch-event
- GitHub hosted Actions product terms: https://docs.github.com/en/site-policy/github-terms/github-terms-for-additional-products-and-features
- Apple Shortcuts HTTP request action: https://support.apple.com/en-mt/guide/shortcuts/apd58d46713f/ios
- Prove Me Wrong skill: https://github.com/Lum1104/prove-me-wrong/blob/main/SKILL.md

**Do not silently promote simulated tests to proof of a live iPhone → Lenovo → DevBox restoration.**
