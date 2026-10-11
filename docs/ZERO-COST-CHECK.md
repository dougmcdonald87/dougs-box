# ZERO-COST-CHECK.md

## Hard rules

1. Only the standard public Windows runner label is used. `DEVBOX_RUNNER_LABEL`
   is allowlisted to `windows-2022`, `windows-2025`, `windows-2025-vs2026`.
2. Actions cache stays at the 10 GB included capacity; never expanded or used as
   a persistence channel.
3. No paid storage, no paid artifacts, no paid CI provider, no automatic
   provisioning of any provider (that is not "a cloud deployment", that is the spec).
4. Never change billing settings programmatically; budget changes are the owner's
   manual work in the GitHub UI.

## Owner's manual Amazon-worth-checking checklist (GitHub side)

1. Settings > Plans: confirm you are on a free plan and note the included usage.
2. Billing > Budgets:
   - Actions budget: 0 with "Stop usage" enabled where supported.
   - Actions Cache Storage budget: 0 with stop enabled.
3. Billing > Alerts: enable included-usage alerts.
4. Settings > Actions > General: disable Actions for org-wide or disable
   unnecessary workflow triggers where helpful.
5. Settings > Environments > devbox: requirement and secrets via UI, never via API.

## Avoiding accidental paid paths

- The workflows pin specific long timeouts and sessions; they do not chain
  automatically. A new session waits for a human.
- `save-state.ps1` uses rest-server, not artifact upload. Small logs are OK if
  diagnostics need them; pattern targets "tiny diagnostics" only.
- The DevBox backs up only HOT and project-sourced files, never the whole disk.

See `docs/OPERATING-MODES.md` for the mode-choice boundary (no fake £0 claim).
