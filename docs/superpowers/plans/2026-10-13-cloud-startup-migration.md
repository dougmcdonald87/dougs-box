# Cloud Startup and Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: use superpowers:executing-plans inline. Doug explicitly authorized autonomous isolated implementation; retain this method. One fresh final reviewer for this new integration scope, one fix pass.

**Goal:** Wire the tested GitHub checkpoint destination into manual DevBox startup with a safe first migration and candidate E workspace.
**Architecture:** Existing bootstrap and startup routines gain explicit opt-in selection. A migration script restores the verified existing source before initializing/publishing cloud state; successful restore emits an owned proof file. Tests use isolated Windows runners, never a desktop or home machine.
**Tech Stack:** PowerShell7, Python3, pinned Restic, GitHub Actions/CLI.
**Spec:** docs/superpowers/specs/2026-10-13-cloud-startup-migration-design.md

## Global constraints
- Home remains default; main/live unchanged; candidate E only; never repurpose D.
- No PR-triggered operational desktop, source backup modification, deletion or cancellation.
- GitHub payload caps remain 8GiB total, 512MiB pieces, 1MiB manifest; no unlimited entitlement claim.
- Source must be restored and verified before first cloud initialization; no silent empty migration.
- Full Windows/all-app persistence remains outside current selected coverage.

## Review focus
- Occupied E: refuse before alias creation or changes to the existing volume.
- Empty/unverified source: no proof, no initialized or published cloud checkpoint.
- Cloud publication failure: retain source metadata/backups and refuse successful migration.
- Existing production channel: migration refuses instead of publishing an accidental blank/new baseline.
- Workflow selection/token propagation: periodic and Finish saves target the chosen cloud backend; default/inspect/duplicate guards remain intact.

### Task 1: candidate workspace and migration transaction
Files: create scripts/cloud-candidate-drive.ps1, scripts/migrate-cloud-persistence.ps1; modify bootstrap.ps1 and restore-state.ps1; create tests/cloud-migration.tests.ps1.
Interfaces: candidate script consumes qualifying physical root, produces E alias/owned directory; bootstrap `-CloudCandidate` selects E only in explicit cloud mode. Restore `-ProofPath <owned path>` emits JSON repoUrl/snapshotId/utc only after successful content processing. Migration consumes current source metadata and key, returns exit0 only after verified cloud publication; failure restores metadata and nonzero.
- [ ] Write real Windows tests: preserve D sentinel, refuse occupied E, create owned E, empty source no proof/no cloud, verified migration, publication failure retains source metadata, existing cloud migration refused.
- [ ] Publish tests in candidate CI and observe feature-unavailable RED.
- [ ] Implement minimal opt-in alias and guarded migration; restore proof emitted only on actual content restore.
- [ ] Run Windows Capture and independent Restore of migration generation; verify C fixture/workspace and scoped backup.
- [ ] Commit/checkpoint evidence and limitations.

### Task 2: manual workflow selection
Files: .github/workflows/devbox.yml, candidate validation workflow, scripts/devbox_lifecycle.py, tests/devbox-lifecycle.tests.py and docs/BACKUP-RECOVERY.md.
Interfaces: workflow input persistence_backend choices home/github-release/migrate-to-github, default home. Selected cloud path bootstraps E; migration restores home once then sets cloud env for later steps. GH_TOKEN reaches cloud connect/first save/session-manager; Windows job contents write only, other jobs unchanged.
- [ ] Add executable YAML contract tests for selected step conditions/env/permissions and refusal of auto dispatch; observe RED.
- [ ] Wire explicit choices into existing flow and pass contract/native migration tests.
- [ ] Run baseline Validate and final independent review; one important-finding fix pass, then checkpoint.
- [ ] Prepare the explicit backend request on main after reviewed opt-in integration, preserving the existing main-only Tailscale trust; keep normal lifecycle payload unchanged. No default switch or Lenovo disconnect before actual production restore acceptance. Main integration is a separate controlled action, not inferred from fixture success.
