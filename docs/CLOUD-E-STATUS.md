# Cloud E: build status

Existing GitHub Windows DevBox stays on its existing C:/D: layout. Candidate storage uses E:. Production devbox.yml, bootstrap, Save/Finish, restore, global CLI, tailnet policy and home repository are unchanged. Feature branch only; do not merge or integrate until actual cloud acceptance.

## Built and verified so far

- Standard-library Python mount policy: exact target/portal/disk/partition/volume/label identity, C/D protection, E collision, existing-session and mounted-partition refusal, GPT/NTFS only. No formatting or initialization.
- Unique 64 KiB canary with fsync and content/hash readback, marker/reparse refusal and truthful proof scope.
- Native Windows read-only mount helper with post-mount verification and rollback limited to its own E mapping and flags.
- GitHub Windows Server2025 disposable VHD tests: wrong identity did not mutate flags; wrong marker rolled back E and readonly flags; valid fixture mounted E read-only; repeat attachment refused while preserving E; writes refused; test-owned disk made writable only inside fixture, device flush/readback passed.
- Native mount RED: run38360785728, helper missing as expected. GREEN: run38361020321, Windows job115174976316 and policy job115174976779 passed. This is real Windows behavior, NOT cloud storage/runtime persistence acceptance.

## Not deployed / remaining access facts

No cloud account, cloud block volume, exported target, provider API credential, actual free-only entitlement or storage-side writer fencing has been identified. Connected GitHub permissions are admin/push; no cloud provisioning capability follows from that. Scratch environment has no GH/OCI/Tailscale/DevBox credential variable. Original iPhone launcher uses phone Keychain; source handover does not transfer its secret. No credential values were printed.

Latest recorded production run38323680245 Windows and relay jobs are completed successfully. Tailscale account is still signed in; observed machine list contains home computers and phone, no active DevBox or relay. This does not invalidate last night's accepted terminal configuration, but its ephemeral execution host is gone. Nothing was cancelled/stopped/restarted in this build task.

## Actual-cloud acceptance before writable use

1. Access the identified existing cloud provider account and prove free-only resource/quota/transfer entitlement; no paid upgrade or trial-only resources.
2. Create/select only a new dedicated data volume and private storage endpoint. No replacement Windows desktop. Preserve existing source history.
3. Export a preformatted disposable test NTFS LUN read-only at the target before Windows connection; prepare its provider-kind/volume marker through controlled provisioning. Do not connect real user data to an unverified writable target.
4. Re-resolve actual runner/relay and bind expected identities from authenticated native inventory. The policy derives the current mount-manager volume GUID from the independently pinned disk/GPT partition identity; it is then rechecked during mount and passed to the bound canary. A fresh GUID needs no user config rewrite. Cloud marker verification remains mandatory.
5. Attach candidate E: read-only and verify source markers. Then separately establish storage-side exclusive ownership and fence stale initiators BEFORE any writable promotion.
6. Use a disposable cloud dataset for flush/crash/reconnect/full-quota/second-writer testing; record acknowledged transaction boundaries and measured cold/warm app performance.
7. Test verified portable app settings/history paths on E:, with existing D: and controls unchanged. Demonstrate home-offline operation and independent backup recovery.
8. Only after acceptance promote writable app use or propose D: cutover. No automated cutover/drive renaming is implemented.

Current files are complete candidate tools, not a completed cloud disk. No fake local VHD is presented as persistent cloud storage.

Final implementation correction: Windows storage GUIDs are runtime mount-manager paths, not the stable cross-run contract. Stable target, disk, GPT partition, label and provider marker remain pinned; the native GUID is captured fresh and guarded for that invocation. Policy regression changing only the mount-manager GUID failed before this correction and passes afterward.

## Final candidate verification

Code commit24a7c6d10bf94dd8eb5ce206595cd2dace84fee5: candidate CI38364069490 passed both policy and native Windows jobs. Policy16/16 and POSIX probe7/7 passed; Windows probe6 passed with the POSIX-only race case skipped. Actual Windows mount/marker/sibling/protected-inventory/readonly/rollback/flush-readback and controlled session A/B cases passed. Existing validation38364069396 covers six baseline jobs; see GitHub for its final status. Native code is never interpreted as actual cloud acceptance.

The exact uploaded DevBox_Start(2).py was read: it retrieves its GitHub token from iPhone Keychain and contains no inline transferable GitHub token. GitHub connector write access is working; cloud GitHub browser is signed out. No new storage credentials, real target or eligible account were identified. Safe live wiring is authorized once an actual DevBox and target are reachable; no working session was killed or restarted.
