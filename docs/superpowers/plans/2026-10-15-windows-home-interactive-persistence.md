# Windows Home interactive persistence implementation plan

Status: planning only. Detailed working copy and continuity evidence are in canonical dev-box-hand-over.zip Library archive. Do not launch runs automatically.

Goal: iPhone graphical access to actual Windows 10 Home guest, explicit user Save and Finish, encrypted immutable full-VM backup, and independent fresh-runner restore/reconnect.

Scope: pilot/windows-home-connection-20261015 only; never touch main, original DevBox, D, Lenovo, production channel. No extra spend.

Task 1: inspect and test actual guest graphical access. Host RDP is not guest desktop proof. Evaluate authenticated private guest agent or console bridge, validate terms, require iPhone input and reconnection.

Task 2: implement narrowly scoped authenticated Save/Finish operator requests with operation IDs, VM identity and generation checks, replay rejection, and separate receipt/completion states. Test denial paths first.

Task 3: extend existing native checkpoints and encrypted Restic publication for interactive guest. Preflight time and capacity, publish immutable generation only after authenticated readback, and inject failed upload to prove prior checkpoint survives.

Task 4: create unique Downloads marker, install test program and change setting from iPhone; Save and Finish; restore on independent runner and verify marker hash, app, setting, VM GUID, distinct host identity and graphical reconnect.

Task 5: whole-branch adversarial review, main/production isolation check, accurate PASS/FAIL report and rolling canonical handover ZIP.

Use focused RED/GREEN tests, commit each stage to pilot only, update ZIP after each stage. Detailed task checklist is packaged in handover archive. Do not conflate static inspection with live tests.