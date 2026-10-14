# Current persistence handoff — 2026-10-14
Last verified ZIP: dev-box-hand-over.zip version127, Library ID libfile_52c1a755c190819186ba037ced7d0f73.
Local workspace exec server is disconnected (409 environment_offline); ZIP cannot currently be rebuilt. Do not claim ZIP128 exists. These changes are durably saved on candidate GitHub branch.

User contract: Windows10Home; normal C disk persistence through fresh outer GitHub hosts; E automatic backup/restore engine; leave user D/Lenovo data alone; zero spending; main unchanged; no duplicate full tests; autonomous continued work and checkpoint each stage.

Confirmed Task2: actual Python3.12.10/doc/preferences/HKCU/machine identity persisted after second guest boot. Full encrypted guest archive4,745,560,617 bytes fits8GiB cap. Fresh outer host restore NOT proven.
Task3: snapshot export falsified. Native run38622490308/job116053248964 changed original VM ID d8a94f09-2253-4b6b-af1a-297010cfb689 to0c6671e4-3c8c-4242-8d4e-bd00f505a793 and name to checkpoint name.
Whole-VM OFF export real Compare-VM/Import-VM test PASSED: run38624468224/job116059992400, head53609175a6b985fa266fe339ae47c13a19e34080. Same ID e1765b6d-d84c-4b57-9424-5b8ff5312576 and same name before/after import, zero incompatibilities, owned E cleanup passed.
Observed RED for new explicit CaptureDataConsistentState policy: run38624608228/job116060464888, headadd6ed602c460fb96db075b4cac0daf42e686955;18cases one assertion failure (not an uncaught error).
Current change replaces Save Export-VMSnapshot with Export-VM -CaptureLiveState CaptureDataConsistentState, retaining ProductionOnly and strict identity/import/hash/parent guards. Policy supports explicit capture and rejects crash/saved/unknown modes. GREEN and actual running Windows A/B restore still pending.

Next:
1. Inspect new candidate CI actual test logs before claiming GREEN.
2. Recover signed ISO URI from completed successful fixture job116007082047 logs, within same dispatch call; functions.store does not persist reliably across turns.
3. Dispatch exactly one full optional install_image+fixture+checkpoint_roundtrip job on current head using original uploaded GitHub PAT source (never print).
4. Test actual SaveA/FinishB restore of program/doc/preferences/HKCU/machine identity. Add controlled guest VSS-service failure attack; no accepted inconsistent receipt.
5. Task4 encrypted publish plus independent fresh-host restore; use existing approved destination/secret, no plaintext credentials in ZIP. Final one whole-branch independent review after four tasks.
6. When workspace reconnects sync candidate source and this handoff into ZIP version128; CRC/local exit0 then replace same Library ID expected127 and apply xattrs. Local source may have uncommitted19test variant; remote source authoritative for changes in this stage.
No full ISO run is active from this stage; only cheap PR guard and Validate tests.
