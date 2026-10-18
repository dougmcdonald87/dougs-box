# Anti-loop and adversarial verification

## A retry is allowed only if
- A concrete observed failure is linked to a run ID, SHA, command and relevant log line.
- A hypothesis predicts a different outcome under a changed input or condition.
- The next check is the cheapest discriminating one.
- Its resource/usage impact and authorization are explicit.
If none apply, stop and hand off; do not rerun the same command to appear busy.

## Failure fingerprint
Record: timestamp, role, branch SHA, run/job ID, command, input digest (never secret values), observed exit/status, one-line cause hypothesis, competing hypothesis, proposed falsifier, owner approval, outcome.

## Prove Me Wrong attack card
Claim: observable property the fix guarantees.
Smallest falsifier: one result that would contradict it.
Strongest competitor: plausible alternative with a different prediction.
Cheapest safe attack: focused test under the relevant state.
Classify result FALSIFIED, SURVIVED, INCONCLUSIVE or UNAVAILABLE. SURVIVED is not proved.

## Hard stop conditions
- Unresolved active job that may be the same task.
- Uncertain target identity or source generation.
- Unexpected billable minutes, new secrets, permissions or storage operations.
- Same failure twice with no new evidence.
- No way to distinguish guest from outer host.
- Test only validates its own mocks rather than the actual acceptance path.

## Time and context economy
Use at most one focused probe per hypothesis, then write an evidence-backed decision. Load only relevant skill/reference. Prefer deterministic scripts for inventory and ledger operations; use an LLM for diagnosis, architecture and review. Stop on proven blockers rather than filling the context with speculation.
