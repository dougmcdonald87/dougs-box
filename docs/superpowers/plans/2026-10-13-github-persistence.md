# GitHub checkpoint integration implementation plan

> Use superpowers:executing-plans inline, with one fresh independent final review.

**Goal:** Add an isolated cloud checkpoint destination to the accepted save/restore contract.
**Architecture:** Standard-library Python generation publication/recovery with GitHub CLI transport; native Windows adapter invokes existing verified Restic routines and gates successful receipts on remote proof.
**Tech Stack:** Python3, PowerShell7, pinned Restic, GitHub CLI and standard Windows CI.
**Spec:** docs/superpowers/specs/2026-10-13-github-persistence-design.md

## Global constraints
- Main/live C/D/startup/controls unchanged until acceptance; home remains default.
- Only encrypted Restic repository assets; no secrets in logs or metadata.
- 8GiB assembled payload, 512MiB pieces, 1MiB manifest; no silent empty restore.
- Draft-to-published commit after download verification; previous generations retained.

## Review focus
- Partial upload/manifest/publish interruption must not produce successful receipt.
- Bad/newer generation must not destroy old backup or restore destination.
- Hostile archive names, symlinks, duplicate entries or inflated size must be refused.
- Concurrent saves/stale local receipts must not authorize Finish incorrectly.
- GitHub failures/timeouts must preserve running workstation and truthful status.

### Task 1: atomic cloud checkpoint transport
Files: scripts/cloud_checkpoint.py; tests/cloud-checkpoint.tests.py.
Produces publish(archive, snapshot_id, receipt_id, remote, max_bytes, part_bytes)->dict and fetch_latest(remote,destination,max_bytes,verify)->dict; GitHubRemote uses environment credential and sanitized bounded CLI calls.
- [x] Write tests for interrupted/corrupt/failed publication, previous recovery, structural/size/repository validation.
- [x] Run python tests/cloud-checkpoint.tests.py; expect feature-unavailable assertion failures.
- [x] Implement protocol and strict archive/manifest validation; run tests; expected green. Commit.

### Task 2: existing save/restore adapter
Files: scripts/cloud-persistence.ps1, common.ps1, connect-persistence.ps1, save-state.ps1, tests/cloud-persistence.tests.ps1 and candidate CI workflow.
Consumes Task1 protocol; produces explicit github-release backend with local encrypted Tools cache, remote-gated receipt and normal existing restore.
- [ ] Add real Windows/Restic Save/Finish interruption and cloud-only startup tests; run expected red before adapter.
- [ ] Implement guarded opt-in adapter without changing default home behavior.
- [ ] Verify first migration, missing-cloud refusal, previous-generation recovery and actual cloud readback. Commit.

### Task 3: final review/checkpoint
- [ ] Run required baseline/new suites, read all outputs, fix only important findings with RED/GREEN.
- [ ] Fresh independent whole-branch review; one fix pass.
- [ ] Checkpoint evidence and blockers; no live activation/merge until accepted.
