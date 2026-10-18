# Single-action execution and Windows acceptance

## On every resume
1. Refresh pilot HEAD from GitHub refs; do not use CP155 as current truth.
2. Fetch latest 20 pilot Actions runs, including the known unresolved run 39073421057. Check status and jobs/logs. If relevant run is active, investigate it; do NOT dispatch duplicate.
3. Identify the exact objective and which proof gate is open. Prefer existing run/log/artifact evidence to repeating expensive work.
4. Propose one smallest read-only or cheap local check. Do not start Windows runners or modify external systems without authorization.
5. Execute only if prerequisites and permissions are satisfied; record observation separately from interpretation.

## Acceptance ladder (each gate independent)
G0 Source and identity: exact pilot branch/commit and approved workflow; original main untouched.
G1 Local Windows guest: actual guest boots; program, Downloads marker/hash, preferences, Windows setting and VM/guest identities observed.
G2 Save/Finish: two immutable accepted encrypted receipts, real readback, canary restore, bound archive size, no incomplete receipt accepted.
G3 Fresh outer host: producer and consumer have distinct host UUID/run IDs; consumer uses exact source SHA and generation; validates all files/parents/manifest/config before import; actual guest boots and state survives.
G4 Remote usability: owner reaches private tailnet outer host, opens actual guest GUI, interacts and reconnects; guest GUI is not inferred from outer RDP.
G5 Independent review: changed code and workflows reviewed against spec, safety, costs and licensing. No feature-complete claim before all required gates.

## Current proof status
Local Save/Finish proof and pilot OIDC tailnet preflight have historical evidence in repo docs; fresh-host guest acceptance and remote guest usability remain unverified in the evidence read for this package. Later runs may change this; refresh before reporting.

## Exact next step
Read the current pilot run list and the status/jobs for 39073421057. If still in progress, investigate its live job status without cancelling or duplicating. Then reconcile the latest successful guard runs with the source SHA. Only after that select a new minimal action.

## Primary evidence pointers
https://github.com/dougmcdonald87/dougs-box/blob/pilot/windows-home-connection-20261015/docs/windows-state-current-handoff.md
https://github.com/dougmcdonald87/dougs-box/blob/pilot/windows-home-connection-20261015/docs/windows-home-pilot-tailnet-runbook.md
https://github.com/dougmcdonald87/dougs-box/actions/runs/39073421057
https://github.com/dougmcdonald87/dougs-box/actions/runs/39075326572
