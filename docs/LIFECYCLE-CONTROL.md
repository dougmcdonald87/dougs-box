# Portable lifecycle control

`python3 scripts/devbox_lifecycle.py status` reads workflow status.
`python3 scripts/devbox_lifecycle.py start` requests exactly one manual start from main after checking for any unfinished DevBox workflow run. It never retries uncertain dispatches or cancels existing runs. The server duplicate guard remains authoritative for cross-device races. Acceptance is not Windows readiness.

Start reads an existing DEVBOX_GITHUB_TOKEN, GH_TOKEN or GITHUB_TOKEN from the execution environment. It needs repository Actions write permission. No token is stored in this source. Doug's original Pythonista script stores its token in the iPhone Keychain; uploading that script does not transfer the token. The connected GitHub tools in this Work task currently expose no workflow-dispatch operation, and scratch has no lifecycle token. Autonomous start from this task is therefore NOT YET runtime verified. Browser GitHub sign-in is a possible separate authenticated route, not established by this CLI adaptation.

Every future manual start installs the lifecycle client as `devbox-control` in its separate Codex relay. Inside that authenticated relay:
`devbox-control save --run-id CURRENT_RUN_ID`
`devbox-control stop --run-id CURRENT_RUN_ID`

For the already-running relay, the exact committed script was installed at `/root/devbox_lifecycle.py`; use `python3 /root/devbox_lifecycle.py` with the same arguments until the next normal start.

Replace CURRENT_RUN_ID with the exact current workflow run. The manifest must match. These invoke the installed Windows request-control.ps1 through the existing pinned `devbox` client, with interactive prompts disabled. Stop uses the same fresh verified Restic backup gate as Finish DevBox Safely. It never calls shutdown or the GitHub cancellation API. A timeout or lost connection means UNKNOWN, not success: inspect current job status and backup receipt before further actions. A successful stop disconnects its Windows and relay connections; that ephemeral relay cannot start the next run after it has ended.

GitHub dispatch documentation: https://docs.github.com/en/rest/actions/workflows?apiVersion=2026-03-10#create-a-workflow-dispatch-event . Modern HTTP 200 with workflow_run_id and legacy HTTP 204 are handled explicitly. Invalid inventories fail closed. `tests/devbox-lifecycle.tests.py` exercises ten controlled boundary attacks without live dispatch or shutdown.
