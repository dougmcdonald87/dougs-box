# Real Windows PowerShell child-process falsification. Never reads Lenovo.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\invoke-save-isolated.ps1')
. (Join-Path $PSScriptRoot '..\scripts\control-queue.ps1')

function Assert([bool]$Good, [string]$Message) {
    if (-not $Good) { throw "ISOLATION TEST FAILED: $Message" }
}

$root = Join-Path ([IO.Path]::GetTempPath()) ('DevBox-Save-Isolation-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root -Force | Out-Null
try {
    $good = Join-Path $root 'good.ps1'
    $failedExit = Join-Path $root 'exit2.ps1'
    $brokenJson = Join-Path $root 'brokenjson.ps1'
    Set-Content -LiteralPath $good -Value "Write-Output 'FAKE GOOD BACKUP'; exit 0" -Encoding utf8
    Set-Content -LiteralPath $failedExit -Value "Write-Output 'FAKE STORAGE ERROR'; exit 2" -Encoding utf8
    Set-Content -LiteralPath $brokenJson -Value @'
$ErrorActionPreference = 'Stop'
'List locks failed' | ConvertFrom-Json -ErrorAction Stop | Out-Null
Write-Output 'SHOULD NEVER GET HERE'
'@ -Encoding utf8

    Assert (Invoke-DevBoxBackupIsolated -SaveScript $good) 'Success did not return success'
    Assert (-not (Invoke-DevBoxBackupIsolated -SaveScript $failedExit)) 'Child exit 2 was reported as success'
    Assert (-not (Invoke-DevBoxBackupIsolated -SaveScript $brokenJson)) 'Fatal JSON exception killed or succeeded in parent'
    Assert (-not (Invoke-DevBoxBackupIsolated -SaveScript (Join-Path $root 'no-file.ps1'))) 'Missing script was accepted'

    $requests = Join-Path $root 'Commands'
    New-Item -ItemType Directory -Path $requests -Force | Out-Null
    $id = [guid]::NewGuid().ToString('N')
    Set-Content -LiteralPath (Join-Path $requests "stop-$id.request") -Value 'CI-only'
    $stop = Invoke-DevBoxControlRequests -ControlPath $root -VerifiedSave {
        param($action)
        Invoke-DevBoxBackupIsolated -SaveScript $brokenJson
    }
    Assert (-not $stop) 'STOP was permitted even though backup died with malformed JSON'
    $response = Get-Content -LiteralPath (Join-Path $requests "stop-$id.result.json") -Raw | ConvertFrom-Json
    Assert (-not $response.success) 'Backup failure incorrectly acknowledged to desktop'
    Assert (-not $response.snapshotId) 'Backup failure reported a new snapshot'

    Write-Output 'WINDOWS FATAL JSON -> SESSION SURVIVES + NO UNSAFE STOP: PASS'
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
