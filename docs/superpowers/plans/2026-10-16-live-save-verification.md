# Live Save Verification Implementation Plan

> For agentic workers: execute inline with superpowers:executing-plans; preserve owner host.

Goal: boot and validate the exact published live Save on a distinct disposable Windows host without ending its producer.
Architecture: opt-in VerifyLiveSave consumer mode; exact generation and source SHA mandatory; authenticated metadata must prove interactive Save, distinct producer/consumer host and run. Existing default completed-producer rules remain unchanged.
Tech stack: PowerShell, Python standard library, GitHub Actions, existing restic transport.
Spec: CP51 publication evidence and owner instruction to progress without losing work.

Global constraints: pilot branch only; no old DevBox/main; no producer stop; no plaintext credentials; consumer contents read permission; exact immutable generation; no hold on consumer and owned consumer cleanup.
Review focus: missing opt-in; active Finish; failed producer; wrong source; same host/run. Tests must refuse each.

Task1: tests/windows-state-transfer.tests.py explicit live Save accepted only with opt-in; active Finish/legacy/failure/same host refused. Run red, implement allow_live_save argument + CLI flag, run green.
Task2: scripts/windows-state-roundtrip.ps1 VerifyLiveSave switch requires source SHA, refuses HoldForOperator combination, accepts active producer only with flag and null conclusion; pass active status + opt-in to authenticated metadata validator. Keep cleanup on consumer.
Task3: workflow restore-live-save-probe choice/job runs Python refusal tests + existing PowerShell tests then exact native restore. Dispatch with CP51 generation/source. Review native result and producer still running. Checkpoint all evidence.
