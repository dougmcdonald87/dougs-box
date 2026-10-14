# Current DevBox handoff — 14 October 2026

Windows 10 Home Save and clean-shutdown backups have both passed real local restore tests. They preserved the VM ID, installed Python, document contents, app preferences, a Windows setting, and the Windows machine identity. Recovery on an independently fresh outer host is still unverified.

## Active work: check this run before starting anything else

- Full encrypted Windows producer retry: https://github.com/dougmcdonald87/dougs-box/actions/runs/38647908553
- Producer job: 116139263038. Source commit: 5f13bc6fa567fdcdea5342a7481cb679a4a8b5e9.
- Started 14 October at 22:28:40 UTC (23:28:40 BST). Status was running when this handoff was written.
- Do not start a duplicate, cancel it, start another main DevBox, or chain workflows automatically.

## Evidence already obtained

1. Full local Save A / Finish B recovery passed in run 38626065555, job 116065415923.
2. Repeat Windows recovery passed in run 38643914142, job 116125964262. Disabling guest vmicvss made native Export-VM refuse Save with NotSupported; the prior complete checkpoint still verified. The service was restored afterward.
3. That producer then failed at a GitHub transport operation. The old error hid the operation and HTTP status, so the cause remains unknown. Do not claim it was fixed or definitely transient.
4. Added sanitized operation/status diagnostics, with an observed failing regression test followed by 21 passing cloud tests. The 15 transfer and 20 manifest tests also pass locally.
5. Draft creation/upload/readback passed in run 38647198460. All operations, including publication, passed with 32 random test bytes in run 38647424106 and a full 536870912-byte chunk in run 38647637617. These are transport probes, not Windows backups.
6. Real small-file encrypted backup/canary/receipt verification passed in run 38644981956. The full earlier Windows package passed local encryption/canary/bounds checks, but no accepted remote receipt was obtained.

## Exact next actions

Read the active producer's completed logs. If it fails again, use its new operation/HTTP diagnostics and measured archive size before changing code. If it succeeds, extract the exact generation from NATIVE ENCRYPTED WHOLE WINDOWS PUBLISHED, confirm the producer ended successfully, then manually dispatch one restore run.

The consumer must run the same source commit as the producer. If this branch has advanced only for documentation/tests, verify the published generation tag points to producer commit 5f13bc6fa567fdcdea5342a7481cb679a4a8b5e9 and dispatch workflow ref=that generation tag, inputs transfer_phase=restore and expected_generation=that exact tag. Do not dispatch the newer branch head and ignore a SHA mismatch.

Fresh recovery must authenticate the encrypted repository, verify the exact producer/generation, require different outer host UUID and run ID, verify every file/hash/parent/config/VM identity before import, and boot/run the actual fixture afterward. A successful hash or transfer alone is insufficient.

After Task 4, perform one fresh-context whole-branch review using the approved plan/spec and the latest source comparison. The local git HEAD is old; review all changed files, including untracked source, against the authoritative GitHub comparison. Earlier f179 comparison is historical; refresh it for the final head. Review preparation notes record two author observations (bootstrap log output in the result stream and a legacy TPM-policy flag); they are not resolved findings yet.

## Constraints and continuity

Keep D and the Lenovo backup repository untouched. Main remains 2ca7bd4ad2c07ce1162d86be84c1a94c9045da55; this work is on the candidate branch and draft PR 29. No additional spending. This trial proves disk state only; RAM/process continuity and guest console/audio/clipboard access are not proven. Do not adopt the guest as the user's desktop before the approved proof/access gates.

Update the same dev-box-hand-over.zip after every completed stage, including exact run IDs, failures, source and next actions. Current latest ZIP before this documentation update is version 146, Library identity libfile_52c1a755c190819186ba037ced7d0f73. The original uploaded credential source is DevBox_Start(4).py, Library identity libfile_73973ccbf9a481918da1705b46cbc816; no plaintext credential is copied into the ZIP.

# Historical handoff entries below

# Current Task4 wiring — 14October2026 22:54BST

Actual full Windows local SaveA and FinishB restore run38626065555/job116065415923 PASSED. Both preserve VM13c1fcd9-31d7-4836-8774-076f365de699, Python3.12.10, point-in-time document/preferences/HKCU/machine identity. Save restored originaldark42/Hide0/doc37414..., Finish restoredlaterlight84/Hide1/doc280D... . Full source verified before owned source unregister; no clone/newGUID. Same outerhost only, freshhostunproved. Portablecredential native test38627404258/job116069950419 PASS.

Task4 now wired but nativeGREEN/packageproducer/consumer notexecuted yet: scripts/windows-state-roundtrip.ps1 publishes only immutable ownedOffFinish, Resticwholebackup/read-data/canaryrestore/receipt, existing8GiBboundedencryptedReleasestransport/readback; no productionchannel. Consumer exactgeneration adapter read-only, producercompleted/samecodeSHA beforedownload, distinctouterUUID/runID, authenticatedmetadata/hash/nativeparents/config/IDbeforeImport, deriveddisposablefixturecredential,actual program/doc/prefs/HKCU/machinechecksafterboot. Workflowmanualtransfer_phase probe(default)/publish/restore. PublishenvironmentdevboxexistingRESTIC_PASSWORD/contentswrite;restorecontentsread/noautochaining. No currentfullISOjobactive. Previous newpublisher presence RED38643235989/job116123703562 ASSERT whole-VM encrypted publisher missing observed; CLI2positive/negative tests RED -> all15transfer+20cloud+20manifestunitGREEN. Need observe currentnativeguard+ValidateGREENbeforeactualpublish.

Next dispatch exactlyone publish with valid officialWin10URI/hash; it rebuildsactualfixtureusingportablecredential,requiresrealA/Broundtrip and disabledvmicvss failure challenge beforepublication. Inspect native VSSfailure actualerrorID; no unrelated failurecounts. Preserveprevious acceptedexport fullinventory. If successread exactgeneration fromcompletedlogs,inventoryproducerended,then manuallydispatchrestoreonSAMErevision with exactexpected_generation. No freshrestorebootclaimbeforeactualfixturepass. Onefinalindependentwholebranchreview aftertasks. Main/D/Lenovo untouched,zeroadditionalspending. Update same ZIP everycompletedstage.

# Historical handoff below (overridden by latest section)

# Current persistence handoff — 2026-10-14
Last verified ZIP: dev-box-hand-over.zip version127, Library ID libfile_52c1a755c190819186ba037ced7d0f73.
Local workspace exec server is disconnected (409 environment_offline); ZIP cannot currently be rebuilt. Do not claim ZIP128 exists. These changes are durably saved on candidate GitHub branch.

User contract: Windows10Home; normal C disk persistence through fresh outer GitHub hosts; E automatic backup/restore engine; leave user D/Lenovo data alone; zero spending; main unchanged; no duplicate full tests; autonomous continued work and checkpoint each stage.

Confirmed Task2: actual Python3.12.10/doc/preferences/HKCU/machine identity persisted after second guest boot. Full encrypted guest archive4,745,560,617 bytes fits8GiB cap. Fresh outer host restore NOT proven.
Task3: snapshot export falsified. Native run38622490308/job116053248964 changed original VM ID d8a94f09-2253-4b6b-af1a-297010cfb689 to0c6671e4-3c8c-4242-8d4e-bd00f505a793 and name to checkpoint name.
Whole-VM OFF export real Compare-VM/Import-VM test PASSED: run38624468224/job116059992400, head53609175a6b985fa266fe339ae47c13a19e34080. Same ID e1765b6d-d84c-4b57-9424-5b8ff5312576 and same name before/after import, zero incompatibilities, owned E cleanup passed.
Observed RED for new explicit CaptureDataConsistentState policy: run38624608228/job116060464888, headadd6ed602c460fb96db075b4cac0daf42e686955;18cases one assertion failure (not an uncaught error).
Current change replaces Save Export-VMSnapshot with Export-VM -CaptureLiveState CaptureDataConsistentState, retaining ProductionOnly and strict identity/import/hash/parent guards. Policy supports explicit capture and rejects crash/saved/unknown modes. GREEN verified on candidate a8413db5c4f547d8f5d9f3d0af346b604193545d: run38624776920/job116061037398 SUCCESS,20manifest tests passed; native empty whole-VM export+copy/import preserved ID c8b0a599-de8f-40ae-bcfe-f9ce4847d4af and exact name, zero compatibility issues, cleanup PASS. Actual running Windows A/B restore still pending.

Next:
1. Inspect new candidate CI actual test logs before claiming GREEN.
2. Recover signed ISO URI from completed successful fixture job116007082047 logs, within same dispatch call; functions.store does not persist reliably across turns.
3. Dispatch exactly one full optional install_image+fixture+checkpoint_roundtrip job on current head using original uploaded GitHub PAT source (never print).
4. Test actual SaveA/FinishB restore of program/doc/preferences/HKCU/machine identity. Add controlled guest VSS-service failure attack; no accepted inconsistent receipt.
5. Task4 encrypted publish plus independent fresh-host restore; use existing approved destination/secret, no plaintext credentials in ZIP. Final one whole-branch independent review after four tasks.
6. When workspace reconnects sync candidate source and this handoff into ZIP version128; CRC/local exit0 then replace same Library ID expected127 and apply xattrs. Local source may have uncommitted19test variant; remote source authoritative for changes in this stage.
No full ISO run is active from this stage; only cheap PR guard and Validate tests.
