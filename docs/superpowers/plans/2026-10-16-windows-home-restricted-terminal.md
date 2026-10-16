# Windows Home Restricted Terminal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans or superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Pair Desktop Commander via Google on the exact disposable GitHub host running the Windows 10 Home VM without allowing the remote process to inherit or access backup-publication secrets.

**Architecture:** Retain the privileged first-party Save/Finish worker. Add a separate-account non-admin terminal sidecar *within the same restore-hold workflow job*, not a second GitHub runner. Gate the sidecar on a native Windows token, process and ACL denial test; encrypt pairing data, hold both processes alive, and clean up on Finish/expiry.

**Tech Stack:** GitHub Actions YAML, Windows PowerShell 7 and scheduled/credentialed local Windows process, Node 24, `node:test`, Windows ACLs, `@actions/artifact`.

**Spec:** `docs/superpowers/specs/2026-10-16-windows-home-terminal-isolation-design.md`

## Global Constraints
- Scope only `pilot/windows-home-connection-20261015`; `main`, old `devbox.yml`, old encrypted storage and personal computers remain untouched.
- No new runner launch without explicit owner approval; GitHub-hosted Windows minutes may count against billing/allowances.
- Never pass GH_TOKEN or RESTIC_PASSWORD to the third-party agent, by environment, file, process arguments, inherited handle or same Windows principal.
- Never expose pairing code, Google token or secrets in Actions logs; preserve current RSA encryption and short-retention artifact mechanics.
- Retain first-party `hold-operator.mjs` as sole Save/Finish publisher; do not give the low-privilege remote account write permission to checkpoint or queue.
- Fail closed on denied/unverifiable Windows identity and access constraints. Do not rely on environment allowlists as the security boundary.
- Preserve exact host/run identity; verify current target before any remote command. Never use stale device IDs.

## Review Focus
1. Windows CreateProcessWithLogon/S4U can fail under GitHub runner context: a launch error must abort pairing, not fall back to privileged spawn.
2. New account may inherit read access to E: whole-guest exports: deny and verify from **agent's actual token** before launching the external tool, without breaking VMMS permissions.
3. Child process may inherit privileged environment or accessible file handles: use separate identity and safe env; native sentinel test.
4. Windows process-tracking might terminate the agent between steps: keep pairing and privileged worker in one job/step, lifecycle supervised.
5. Lost pairing/worker, expiry, or premature runner shutdown must leave existing encrypted checkpoint unchanged and never report Save success.

---

### Task 1: Fail-closed restricted Windows identity and access guard
**Files:**
- Create `scripts/windows-home-restricted-agent.ps1`: provision ephemeral non-admin local account and launch a bounded process with `Start-Process -Credential`; explicitly verify distinct SID/group denial, protected control ACL and guest-storage roots.
- Create `tests/windows-home-restricted-agent.tests.py`: static policy/order checks; include a harmless native Windows sentinel-denial test mode.

**Interfaces:** `Start-WindowsHomeRestrictedAgent -RunId <string> -ControlDir <string> -ProbeRoot <string> -Command <string> -OutputPath <string>` returns `{sid,pid}` only after credentialed process identity and denial checks.

- [ ] Step 1: Write Python static tests that require exact pilot-only guards, non-admin account, no production fallback and deny checks for control/VM root. Run; confirm RED on missing script.
- [ ] Step 2: Implement the minimal PowerShell helper; run Python tests; confirm GREEN.
- [ ] Step 3: Native disposable Windows sentinel test: fake string in protected privileged file; actual restricted token must fail to read and write control and E guest roots. RED/GREEN explicitly observed before real agent launch; if the runner cannot start with distinct token, fail closed.
- [ ] Step 4: Record failures and stop; no external pairing when this gate fails.

### Task 2: Pairing sidecar and privileged-worker supervision
**Files:**
- Create `.github/actions/pilot-device/restricted-pairing.mjs` to monitor a restricted child output file, encrypt the pairing payload with pinned public RSA modulus, upload a short-retention Actions artifact, and supervise child identity/lifetime.
- Create `.github/actions/pilot-device/restricted-pairing.test.mjs` using no real credentials or network.
- Modify `.github/actions/pilot-device/hold-operator.mjs` only to safely orchestrate supervised sidecar alongside the existing first-party worker (or provide a separate supervisor module importing it).

**Interfaces:** `runRestrictedPairing({runId,controlDir,agentPid,outputFile,publicModulus,artifactClient}) -> {ready,artifactId}`; `holdOperatorSession` remains authoritative.

- [ ] Step 1: RED tests for artifact secrecy, wrong run ID, dead child, no pairing, and worker Save/Finish continuity.
- [ ] Step 2: Implement minimal supervision; GREEN tests and existing operator suite.
- [ ] Step 3: Confirm no privileged fallback; protected fields never entered child environment or on-disk public artifacts.

### Task 3: Same-host workflow integration and guard tests
**Files:**
- Modify `.github/workflows/windows-state-probe-validate.yml` only within `restore-hold`.
- Create `tests/windows-home-pairing-workflow.tests.py` to parse/check actual workflow ordering and scoping.

- [ ] Step 1: RED test: require guest restore first, restricted native denial check next, then fresh pairing and privileged worker in **same job**, no pairing in another host and no unrestricted `index.mjs`.
- [ ] Step 2: Add bounded pilot-only steps and environment-scoped public modulus. Ensure all externally executed code has the low-privilege token. GREEN on workflow tests.
- [ ] Step 3: Run existing PowerShell/Python/Node tests applicable in current environment; report unavailable Windows-only tests explicitly.

### Task 4: Independent gate and rollout
**Files:** Update handover roll-forward with exact commit, tests, next action and SHA-256 manifest.

- [ ] Step 1: Prove Me Wrong: attempt same-user secret-read scenario then restricted-token denial on disposable Windows only; classify outcome. Do not interpret Linux/static checks as native OS proof.
- [ ] Step 2: Recheck original `main` SHA unchanged, production channel unused, pilot workflow not launched.
- [ ] Step 3: Only when native Windows safety test passes, arrange one owner-authorised pilot `restore-hold` launch and fresh Google authorization. Check current GitHub run ID on connected runner.
- [ ] Step 4: Validate real Save receipt → Finish receipt → independent fresh-host restore and update the rolling ZIP. Failures remain failures, not green CI.

## Execution notes
- Never let a failed native isolation test be overridden by static test success.
- Preserve the original producer seed. Never overwrite `devbox.yml` or launch `main`.
- The available GitHub connector writes commit files on the isolated pilot branch only; code changes should be narrowly staged and verified after each write.
- No native Windows runner has been launched in this planning stage.