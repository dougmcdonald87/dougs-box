# Windows Home pilot: isolated tailnet access runbook

**Status (2026-10-15):** Dedicated pilot Tailscale GitHub OIDC authentication **LIVE VERIFIED**; Windows 10 Home VM GUI, RDP reachability, Save/Finish and new-runner recovery remain **UNTESTED**. This document is for the isolated branch `pilot/windows-home-connection-20261015`. It does not modify `main`, the existing DevBox, or its original Tailscale Workload Identity Federation credential.

## Why a separate credential is necessary

`scripts/check-tailscale-oidc.ps1` explicitly validates the original production workflow as `dougmcdonald87/dougs-box/.github/workflows/devbox.yml@refs/heads/main`. Its federated identity is not a valid credential for an unrelated branch/workflow. The Windows Home pilot needs its own trust credential, scoped to its own workflow and identity.

The pilot `restore-hold` job now directly specifies the **separate public Tailscale OIDC Client ID** provided by the owner (pilot branch only), so no GitHub Actions variable creation is needed. The workflow performs an OIDC preflight and refuses to restore the guest unless its pilot-specific identity claims match. **A Client ID is not proof that Tailscale has the tag, grants, or correct credential scopes.**

## One-time external requirements — owner/admin controls

1. In the Tailscale admin console, create a **separate** tag `tag:windows-home-pilot` rather than reusing the original `tag:github-devbox` identity. Do not weaken any existing Grants or tag ownership.
2. Create a new federated identity credential with the writable `auth_keys` scope and the exact pilot tag. Bind to GitHub Actions OIDC issuer `https://token.actions.githubusercontent.com`, the environment `devbox` subject `repo:dougmcdonald87@220090710/dougs-box@1414179011:environment:devbox`, and workflow reference `dougmcdonald87/dougs-box/.github/workflows/windows-state-probe-validate.yml@refs/heads/pilot/windows-home-connection-20261015`. Its audience is the value supplied by Tailscale; the code expects `api.tailscale.com/<dedicated client ID>`.
3. Add only the minimally necessary policy allowing the owner's already-authorized iPhone tailnet identity to reach `tag:windows-home-pilot` on TCP port 3389. Do not allow public RDP or broad tailnet access. The Windows firewall also restricts incoming RDP to Tailscale's 100.64.0.0/10 range.
4. **GitHub Client ID wiring is already completed on the isolated pilot branch**. Do not create a GitHub variable, paste a GitHub personal access token, change the original `DEVBOX_OIDC_CLIENT_ID`, or add an OAuth client secret. Verify that the pilot Tailscale credential itself has `auth_keys` write scope restricted to `tag:windows-home-pilot`, that the tag exists and is owned, and that the iPhone has only the necessary private RDP grant.

This is a setup prerequisite, not authority for the assistant to change Tailscale's trust settings or create a billable GitHub-hosted Windows run.

Official references: https://tailscale.com/docs/integrations/github/github-action and https://tailscale.com/docs/features/workload-identity-federation . Note: Tailscale identity federation requires version >=1.90.1, the `auth_keys` scope, a configured tag, and GitHub `id-token: write` permissions.

## Verified pilot OIDC and Tailnet admission — 2026-10-15

**RESULT: PASSED** — GitHub Actions isolated `workflow_dispatch` run [38814390414](https://github.com/dougmcdonald87/dougs-box/actions/runs/38814390414), job `116695286219` ("Pilot tailnet connection preflight (no VM)"). This was dispatched through an owner-authorized one-shot kickoff [38814376135](https://github.com/dougmcdonald87/dougs-box/actions/runs/38814376135), because the connected GitHub tool could not directly issue `workflow_dispatch` and the local container lacked outbound DNS. The one-shot trigger file was then **deleted** from the pilot branch at commit `9aceff59e3bc3ae7d652749555760b492d9e2417`.

Live job log evidence:

- `PILOT_TAILNET_OIDC_CONTEXT_VERIFIED=true`
- `Join isolated tailnet using the dedicated pilot identity` → step success
- `PILOT_TAILNET_PREFLIGHT_OK=100.x.x.x` → private tailnet IPv4 issued
- Post-job Tailscale logout completed. No persistent pilot device was left connected.
- All other jobs, including **restore-hold**, **publish**, **restore**, and **probe**, were **skipped**. No Windows runner, VM restore, RDP or persistence action occurred.

**Prove Me Wrong:** The real authentication path survived the controlled first-party pilot credential test and would have failed on wrong GitHub OIDC claims or inability to obtain a private Tailscale IPv4. However, this does **not** prove iPhone policy reachability, RDP, Hyper-V guest GUI, installed-app persistence, or complete Save/Finish recovery. No claim of end-to-end completion.

## First: small pilot Tailnet authentication test (no Windows VM)

The owner reports that `tag:windows-home-pilot` and the new Tailscale OIDC credential with `auth_keys` Write are already configured. Do **not** ask them to create the tag again. The new public Client ID is already committed on the isolated pilot branch, so **do not** require a GitHub variable or personal access token.

Before spending time restoring Windows, use the GitHub Actions workflow **Windows Home persistence probe guards** at https://github.com/dougmcdonald87/dougs-box/actions/workflows/windows-state-probe-validate.yml . Select branch `pilot/windows-home-connection-20261015`, then set **transfer_phase = tailnet-preflight** and click **Run workflow** once. This job runs on `ubuntu-latest`, is manual only, is limited to 12 minutes, requests only `contents: read` and `id-token: write`, and does **not** touch Windows, RDP, the restored guest or any original DevBox storage. GitHub-hosted runner usage may count against plan allowances.

Evidence required in the single run logs: `PILOT_TAILNET_OIDC_CONTEXT_VERIFIED=true`, then `PILOT_TAILNET_PREFLIGHT_OK=100.x.x.x`. A successful Tailscale address proves pilot OIDC authentication and tag acceptance from GitHub, but **does not prove iPhone-to-RDP grant, Hyper-V guest GUI or persistent VM save**. If this fails, inspect only its error and correct that specific dependency; do not launch the long `restore-hold` to guess.

## Manual, bounded end-to-end acceptance (only after authorization)

- Start `windows-state-probe-validate.yml` on the **pilot branch** with `transfer_phase=restore-hold`, `expected_generation=devbox-checkpoint-v1-ci-38647908553-1-20261014T225101Z-eb2366ef7dc34ea4aee45c30bbc721b6` and empty `expected_source_sha` (known pinned original source hash is selected internally). Do not launch the original `devbox.yml`.
- Verify OIDC preflight and a private `ISOLATED_PILOT_TAILSCALE_IP=100.x.x.x` appear in GitHub Actions logs. `RDP ready` alone proves only the outer host, not the guest.
- On iPhone Tailscale, open Microsoft Windows App to that private IP on RDP/3389 using the existing authorised RDP account (`runneradmin` or the recorded fallback `devbox`). Open the desktop shortcut **Windows 10 Home VM**. Confirm the actual guest is displayed and accepts touch/keyboard input; reconnect and confirm again.
- Inside **the guest**, create a unique Downloads marker with recorded SHA256, install one approved test application and change a benign Windows/app setting; do not install secrets in the guest.
- From the outer host's desktop click **Windows 10 Home Save** and wait for an immutable encrypted generation receipt (the status window stays open); then **Windows 10 Home Finish** and wait for a second verified receipt before closing. A request submitted message is NOT a verified Save.
- On a genuinely different manual runner, restore the exact approved generation with its **producer commit SHA** in `expected_source_sha`. Check producer/consumer IDs differ, VM GUID and Downloads hash are identical, app and setting survive, and the iPhone graphical connection works again.

**Outstanding risk:** This full sequence has never passed on a live Windows runner. GitHub-hosted Windows minutes may have a financial cost or usage limit. No manual run is started by these instructions.
