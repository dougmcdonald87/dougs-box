$ErrorActionPreference='Stop';Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '../scripts/windows-state-roundtrip.ps1')
if(-not(Get-Command Get-WindowsStateFreshRestoreReceipt -ErrorAction SilentlyContinue)){throw 'ASSERT: strict-mode-safe restore receipt selector missing'}
$receipt=[pscustomobject]@{freshHostRestored=$true;vmId='owned';root='owned-root'}
$noise=@('restic stdout',[pscustomobject]@{eligible=$true},[pscustomobject]@{phase='bootstrap'},42,$null)
$result=Get-WindowsStateFreshRestoreReceipt -Parts @($noise+$receipt+'held marker')
if($result.vmId -cne 'owned'){throw 'ASSERT: actual receipt lost among unrelated native output'}
function Refuse($parts){$failed=$false;try{Get-WindowsStateFreshRestoreReceipt -Parts $parts|Out-Null}catch{$failed=$true};if(-not $failed){throw 'ASSERT: missing/ambiguous/nonboolean receipt accepted'}}
Refuse $noise
Refuse @($receipt,$receipt)
Refuse @([pscustomobject]@{freshHostRestored='true'})
Refuse @([pscustomobject]@{freshHostRestored=$false})
Write-Host 'STRICT RESTORE RECEIPT: PASS (5 cases)'
