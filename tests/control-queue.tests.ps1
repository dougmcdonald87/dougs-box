# Adversarial control-queue tests. Uses fake backups and disposable temp files.
# No Lenovo, Tailscale, GitHub workflow dispatch or live runner touched.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot '..\scripts\control-queue.ps1')

$root = Join-Path ([IO.Path]::GetTempPath()) ('DevBox-Controls-Test-' + [guid]::NewGuid().ToString('N'))
$cmd = Join-Path $root 'Commands'
New-Item -ItemType Directory -Path $cmd -Force | Out-Null
$script:calls = 0
$script:last = Join-Path $root 'last-backup.json'

function Assert([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "CONTROL QUEUE FAIL: $Message" }
}
function Request([string]$Action, [string]$Id) {
    $f = Join-Path $cmd "$Action-$Id.request"
    Set-Content -LiteralPath $f -Value 'test' -Encoding utf8
    return $f
}
function Result([string]$Action, [string]$Id) {
    return (Get-Content -LiteralPath (Join-Path $cmd "$Action-$Id.result.json") -Raw | ConvertFrom-Json)
}
function Write-TestBackup([string]$Id) {
    @{ snapshotId = $Id; utc = [DateTime]::UtcNow.ToString('o') } |
        ConvertTo-Json | Set-Content -LiteralPath $script:last -Encoding utf8
}
try {
    # Attack 1: save returns failure; stop MUST NOT happen.
    $id1 = [guid]::NewGuid().ToString('N')
    Request stop $id1 | Out-Null
    $stop = Invoke-DevBoxControlRequests -ControlPath $root -VerifiedSave {
        param($action)
        $script:calls++
        return $false
    }
    Assert (-not $stop) 'Failed backup stopped session'
    Assert (-not (Result stop $id1).success) 'Failed backup claimed success'

    # Attack 2: callback reports success but did NOT write new metadata.
    Write-TestBackup 'previous-snapshot'
    $id2 = [guid]::NewGuid().ToString('N')
    Request stop $id2 | Out-Null
    $stop = Invoke-DevBoxControlRequests -ControlPath $root -VerifiedSave {
        param($action)
        $script:calls++
        return $true
    }
    Assert (-not $stop) 'Stale backup metadata allowed shutdown'
    Assert (-not (Result stop $id2).success) 'Stale metadata falsely reported success'

    # Attack 3: a fresh snapshot permits stop.
    $id3 = [guid]::NewGuid().ToString('N')
    Request stop $id3 | Out-Null
    $stop = Invoke-DevBoxControlRequests -ControlPath $root -VerifiedSave {
        param($action)
        $script:calls++
        Write-TestBackup 'new-verified-snapshot'
        return $true
    }
    Assert ($stop) 'Fresh verified backup did not permit stop'
    Assert ((Result stop $id3).success) 'Fresh backup not acknowledged'
    Assert ((Result stop $id3).snapshotId -eq 'new-verified-snapshot') 'Wrong snapshot reference'

    # Attack 4: manual save always leaves the job running.
    $id4 = [guid]::NewGuid().ToString('N')
    Request save $id4 | Out-Null
    $stop = Invoke-DevBoxControlRequests -ControlPath $root -VerifiedSave {
        param($action)
        $script:calls++
        Write-TestBackup 'save-only-snapshot'
        return $true
    }
    Assert (-not $stop) 'Save-only request incorrectly stopped runner'
    Assert ((Result save $id4).success) 'Save-only snapshot not acknowledged'

    # Attack 5: unrecognised files cannot run arbitrary actions.
    Set-Content -LiteralPath (Join-Path $cmd 'evil-code.request') -Value 'Write-Host unsafe'
    $prior = $script:calls
    $stop = Invoke-DevBoxControlRequests -ControlPath $root -VerifiedSave {
        param($action)
        $script:calls++
        return $true
    }
    Assert (-not $stop) 'Malformed request caused stop'
    Assert ($script:calls -eq $prior) 'Unknown command executed'

    # Attack 6: processed commands never run twice.
    Assert (-not (Test-Path -LiteralPath (Join-Path $cmd "stop-$id3.request"))) 'Completed request not removed'
    Assert (-not (Invoke-DevBoxControlRequests -ControlPath $root -VerifiedSave { throw 'duplicate' })) 'Duplicate request ran'

    # Attack 7: exception in backup callback must not permit stop.
    $id7 = [guid]::NewGuid().ToString('N')
    Request stop $id7 | Out-Null
    $stop = Invoke-DevBoxControlRequests -ControlPath $root -VerifiedSave { throw 'simulated storage outage' }
    Assert (-not $stop) 'Exception allowed shutdown'
    Assert (-not (Result stop $id7).success) 'Exception falsely reported backup success'

    Write-Output 'DEVBOX CONTROL ADVERSARIAL TESTS: 7 PASS'
} finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
