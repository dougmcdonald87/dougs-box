# iPhone Start + verified DevBox Stop — rollout guide

**Status: tested on isolated CI runners; activation requires merging the PR and launching a NEW DevBox. Not tested on Doug's iPhone or over live RDP.**
Scope: temporary GitHub-hosted Windows runner only. No changes to Lenovo, HP, RustDesk, Z:, Tailscale tags or permissions.

## Usage and cost gate — read BEFORE enabling

GitHub Actions is for software development lifecycle workflows. GitHub's [product terms](https://docs.github.com/en/site-policy/github-terms/github-terms-for-additional-products-and-features) explicitly restrict GitHub-hosted runners to the production, testing, deployment or publication of the software project associated with the repository. This shortcut is only suitable for compliant development/testing use; it does not authorize an unrestricted personal cloud desktop.

Do **not** set up an unattended six-hour restart loop. Keep one run at a time and check GitHub billing, usage and environment approval settings manually. A public repository does not automatically make otherwise unrelated compute use acceptable.

## A. Verified STOP from the RDP desktop

The future DevBox workflow installs two **Windows Public Desktop** links:

- `Save DevBox State Now`: request a new verified Restic snapshot and continue working.
- `Finish DevBox Safely`: request a NEW verified Restic snapshot. The GitHub session job exits **only after** snapshot metadata is confirmed updated. If the backup fails or is stale, the session continues and reports FAILURE. At its configured deadline, GitHub can still terminate the job regardless of the request, so **nothing guarantees preservation against external termination**.

Both shortcuts use `scripts/request-control.ps1`, copied at startup to `<DevBoxRoot>\Tools\DevBoxControls\request-control.ps1`. They create one unique, locally named file in `<DevBoxRoot>\Control\Commands`, wait for the runner's response, and display the result. The local RDP process **never receives** Restic/GitHub credentials. Only `session-manager.ps1` runs the backup and ends the job.

On the RDP desktop, double-click the appropriate shortcut. Do **not** use the GitHub `Cancel workflow` button for routine shutdown: GitHub may interrupt a backup. If no result is displayed, **do not assume a successful backup**.

This is not a native iPhone home-screen Stop shortcut. It is a desktop control reached through the already-working Windows App Remote Desktop session.

## B. Optional one-tap START using Apple's built-in Shortcuts app

**Prerequisites:** Confirm compliant use above; merge/test this PR first; ensure a prior DevBox run is not already active. The existing `devbox` GitHub Environment approval, if required, is **not bypassed** by the API.

GitHub officially supports starting a `workflow_dispatch` workflow from a GitHub API request, using a **fine-grained personal access token with Actions: Write** access to the **single `dougmcdonald87/dougs-box` repository**.

1. On your normal iPhone GitHub session, go to GitHub account Settings → Developer settings → Personal access tokens → Fine-grained tokens. Create a token with a short expiration, selected repository `dougmcdonald87/dougs-box` only, and repository permission **Actions: Read and write**. Do not add unrelated repository privileges. Do not put the token in the GitHub repository, screenshots, or chat.
2. Open the built-in **Shortcuts** app → New Shortcut, name it `Start DevBox`. Add a `Text` action with `Bearer YOUR_FINE_GRAINED_TOKEN` (this stores the token in the Shortcut configuration—**anyone with access to the Shortcut can reveal it**; do not share/export the Shortcut).
3. Add a `URL` action with the *preflight* endpoint:
   `https://api.github.com/repos/dougmcdonald87/dougs-box/actions/workflows/devbox.yml/runs?per_page=10`
4. Add `Get Contents of URL` with method **GET** and headers `Authorization` set to the output of the token Text action, `Accept: application/vnd.github+json`, and `X-GitHub-Api-Version: 2022-11-28`.
5. Extract the `workflow_runs` list from the GET JSON result with `Get Dictionary Value`; use `Repeat with Each` to inspect every run's `status`. If any run is `in_progress`, `queued`, `waiting`, `pending` or `requested`, display `DevBox already active or starting; no new launch` and invoke `Stop This Shortcut`. **This check reduces but does not eliminate races**.
6. If no active run exists, add a second `URL` action:
   `https://api.github.com/repos/dougmcdonald87/dougs-box/actions/workflows/devbox.yml/dispatches`
7. Add another `Get Contents of URL` with **POST**, the same three HTTP headers, and **JSON** body containing `ref` with value `main`. Leave `inputs` absent. An HTTP **204 No Content** is a successful dispatch; there may be no response to display. If GitHub responds 401/403, check the token permissions and whether approval is needed; do **not** blindly retry.
8. Add `Show Notification` text `Start requested — check GitHub Actions for READY and any devbox approval`. Optional: `Open URLs` to:
   `https://github.com/dougmcdonald87/dougs-box/actions/workflows/devbox.yml`
9. Test first with only GET and inspect the returned statuses. Then, only **when the previous DevBox has stopped**, test one manual dispatch. Add the Shortcut to the iPhone Home Screen after end-to-end verification.

**Important:** The current GitHub workflow has `concurrency.cancel-in-progress: true`. A duplicate POST, including a race between preflight and POST, **can cancel a running DevBox**. This is why we do not claim a bulletproof one-tap START. Server-side concurrency hardening must be reviewed separately before making a fully hands-off shortcut.

GitHub API reference: https://docs.github.com/en/rest/actions/workflows?apiVersion=2022-11-28#create-a-workflow-dispatch-event

Apple iPhone Shortcuts REST reference: https://support.apple.com/en-mt/guide/shortcuts/apd58d46713f/ios

## C. Readiness and reconnect

The iPhone Shortcut triggers a new **GitHub job**, it does not create a persistent named Windows PC. Each new session has a new `devbox-<run-id>` Tailscale name. Wait for `DEVBOX READY` in the GitHub job, find that new tailnet device, then connect using Windows App on the iPhone. Existing Lenovo Restic snapshots are restored by the workflow, within the configured 3 GiB automatic-restore limit.

## D. Rule 1: adversarial evidence and limitations

| Challenge | Test | Result |
|---|---|---|
| Stop with failed backup | Fake callback returns false | CI test must show session continues |
| Stop with stale metadata | Fake callback returns true without writing NEW metadata | CI test must reject stop |
| Stop with NEW backup proof | Fake callback writes a fresh snapshot ID | CI test must permit stop |
| Save-only request | Fake callback writes a fresh snapshot ID | CI test must keep session running |
| Unknown command | Request filename outside exact allowlist | CI test must ignore it |
| Repeated request | Process once and call queue again | CI test must not repeat operation |
| Backup throws | Simulated storage outage | CI test must reject stop |
| Windows public desktop links | Create two .lnk shortcuts on disposable Windows runner | Windows CI smoke required |
| Actual RDP click -> actual Lenovo Restic -> normal job exit -> restored work | Requires authorized future live session | **UNVERIFIED** |
| iPhone Shortcut -> GitHub API -> environment approval -> RDP | Requires owner's iPhone token & approval | **UNVERIFIED** |

**No test that merely mocks the backup can prove live Lenovo preservation**. Never use a fake backup test to claim real end-to-end recovery.

### Live-run isolation

This PR changes the next run **only if merged into main**. The currently running DevBox checks out its workflow/scripts from its original commit and must not be interrupted. PR CI runs on disposable separate jobs.
