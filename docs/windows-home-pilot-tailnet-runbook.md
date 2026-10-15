# Windows Home pilot: isolated tailnet access runbook

**Status (2026-10-15):** Prepared in code, NOT provisioned or live-tested. This document is for the isolated branch `pilot/windows-home-connection-20261015`. It does not modify `main`, the existing DevBox, or its original Tailscale Workload Identity Federation credential.

## Why a separate credential is necessary

`scripts/check-tailscale-oidc.ps1` explicitly validates the original production workflow as `dougmcdonald87/dougs-box/.github/workflows/devbox.yml@refs/heads/main`. Its federated identity is not a valid credential for an unrelated branch/workflow. The Windows Home pilot needs its own trust credential, scoped to its own workflow and identity.

The pilot `restore-hold` job now fails **before** restoring the guest if `PILOT_TAILSCALE_OIDC_CLIENT_ID` is absent. That prevents a long-running, inaccessible VM session.

## One-time external requirements — owner/admin controls

1. In the Tailscale admin console, create a **separate** tag `tag:windows-home-pilot` rather than reusing the original `tag:github-devbox` identity. Do not weaken any existing Grants or tag ownership.
2. Create a new federated identity credential with the writable `auth_keys` scope and the exact pilot tag. Bind to GitHub Actions OIDC issuer `https://token.actions.githubusercontent.com`, the environment `devbox` subject `repo:dougmcdonald87@220090710/dougs-box@1414179011:environment:devbox`, and workflow reference `dougmcdonald87/dougs-box/.github/workflows/windows-state-probe-validate.yml@refs/heads/pilot/windows-home-connection-20261015`. Its audience is the value supplied by Tailscale; the code expects `api.tailscale.com/<dedicated client ID>`.
3. Add only the minimally necessary policy allowing the owner's already-authorized iPhone tailnet identity to reach `tag:windows-home-pilot` on TCP port 3389. Do not allow public RDP or broad tailnet access. The Windows firewall also restricts incoming RDP to Tailscale's 100.64.0.0/10 range.
4. Put the **new dedicated client ID** in the GitHub repository or `devbox` Environment Actions variable `PILOT_TAILSCALE_OIDC_CLIENT_ID`. Do not paste credentials into the repo or the handover. Do not replace `DEVBOX_OIDC_CLIENT_ID`.

This is a setup prerequisite, not authority for the assistant to change Tailscale's trust settings or create a billable GitHub-hosted Windows run.

Official references: https://tailscale.com/docs/integrations/github/github-action and https://tailscale.com/docs/features/workload-identity-federation . Note: Tailscale identity federation requires version >=1.90.1, the `auth_keys` scope, a configured tag, and GitHub `id-token: write` permissions.

## Manual, bounded end-to-end acceptance (only after authorization)

- Start `windows-state-probe-validate.yml` on the **pilot branch** with `transfer_phase=restore-hold`, `expected_generation=devbox-checkpoint-v1-ci-38647908553-1-20261014T225101Z-eb2366ef7dc34ea4aee45c30bbc721b6` and empty `expected_source_sha` (known pinned original source hash is selected internally). Do not launch the original `devbox.yml`.
- Verify OIDC preflight and a private `ISOLATED_PILOT_TAILSCALE_IP=100.x.x.x` appear in GitHub Actions logs. `RDP ready` alone proves only the outer host, not the guest.
- On iPhone Tailscale, open Microsoft Windows App to that private IP on RDP/3389 using the existing authorised RDP account (`runneradmin` or the recorded fallback `devbox`). Open the desktop shortcut **Windows 10 Home VM**. Confirm the actual guest is displayed and accepts touch/keyboard input; reconnect and confirm again.
- Inside **the guest**, create a unique Downloads marker with recorded SHA256, install one approved test application and change a benign Windows/app setting; do not install secrets in the guest.
- From the outer host's desktop click **Windows 10 Home Save** and wait for an immutable encrypted generation receipt (the status window stays open); then **Windows 10 Home Finish** and wait for a second verified receipt before closing. A request submitted message is NOT a verified Save.
- On a genuinely different manual runner, restore the exact approved generation with its **producer commit SHA** in `expected_source_sha`. Check producer/consumer IDs differ, VM GUID and Downloads hash are identical, app and setting survive, and the iPhone graphical connection works again.

**Outstanding risk:** This full sequence has never passed on a live Windows runner. GitHub-hosted Windows minutes may have a financial cost or usage limit. No manual run is started by these instructions.
