# Universal DevBox agent contract (all platforms)
Goal: preserve exact progress while safely advancing isolated Windows 10 Home DevBox persistence and remote-access acceptance. Do not waste compute, loop through known failures, or conflate old/new machines.

## Before any operation
1. Read state/CURRENT.json and references/MACHINE_REGISTRY.md. Their timestamps are historical, not live.
2. Refresh the pilot branch SHA and latest Actions runs using GitHub read-only tools. Check for running jobs before proposing new ones.
3. For device operations, list Desktop Commander devices, select by current ID AND verified hostname/role, ping, then read-only inspect. Offline means offline. GitHub Actions runner hostnames are ephemeral.
4. Print an identity card: target role, repo, branch, SHA, run ID, host identity, machine/guest identity, source evidence, permission scope. Unknown values must be marked UNKNOWN.
5. Select exactly one smallest next action from references/ACCEPTANCE.md; stop if its preconditions are missing.

## Hard boundaries
- Original DevBox is the production main workflow; never edit, start, cancel, or migrate it during pilot work without explicit new authorization.
- Pilot source branch is pilot/windows-home-connection-20261015. This kit branch is documentation only and MUST NOT be merged into pilot or main.
- Outer GitHub runner, Windows 10 Home Hyper-V guest, original DevBox, and personal HP/Lenovo machines are distinct entities. A device name is not a stable runner identity.
- Preserve Lenovo and D: storage. No deleting, pruning, force push, history rewrite, token disclosure, Tailscale policy weakening, public RDP, or paid/billable job dispatch without explicit authorization.
- No claim of full recovery until independently fresh outer-host restore, actual guest boot, identity/app/file/setting checks and remote usability are proven.
- Never call a workflow success proof of the feature unless the relevant acceptance steps ran.
- GitHub-hosted Actions has runtime and acceptable-use limits. Do not design an always-on desktop that circumvents those limits.

## Anti-drift and evidence
- Use the same terminology in references/MACHINE_REGISTRY.md.
- If a command fails, record command, inputs, observed error, run/SHA, hypothesis, smallest discriminating next check. Do not repeat unchanged inputs more than once.
- Prove Me Wrong gate: before accepting a nontrivial fix, write a 4-line attack card and perform one cheapest safe falsifier. Classify survived/falsified/inconclusive/unavailable.
- Every completion claim needs direct output or linked log evidence. Do not claim tests passed if not run.
- After each meaningful stage, append a local checkpoint using scripts/continuity.py and prepare a handoff with exact next action. Never overwrite prior evidence.

## When to use specialist skills
See references/SKILL_ROUTER.md. Skills/plugins in ChatGPT do not auto-install into OpenCode; absence of a skill does not waive its safety invariant.

## End-of-turn handoff format
Goal; exact target and identity; verified done; attempted/not accepted; active blockers; run IDs/SHAs/log links; changed files; test evidence; cheapest next action; required permission; no-go list. Update state locally and give the user the checkpoint location.
