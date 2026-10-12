# restic-diagnostics.ps1 — actionable error categories without disclosing
# source paths or file contents in logs of a potentially PUBLIC GitHub repo.
Set-StrictMode -Version Latest

function Get-DevBoxResticErrorDiagnostics {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Lines,
          [Parameter(Mandatory)][int]$ExitCode)
    $errorsFound = 0
    $examples = New-Object System.Collections.Generic.List[string]
    foreach ($line in $Lines) {
        $item = $null
        try { $item = [string]$line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
        if ([string]$item.message_type -ne 'error') { continue }
        $errorsFound++
        if ($examples.Count -ge 8) { continue }
        $problem = ''
        if ($null -ne $item.PSObject.Properties['error']) {
            $problem = ($item.error | ConvertTo-Json -Compress -Depth 7)
        }
        $category = if ($problem -match '(?i)access.{0,8}denied|permission.{0,8}denied|unauthori[sz]ed') {
            'permission'
        } elseif ($problem -match '(?i)another process|sharing violation|file.{0,8}used|locked') {
            'locked-file'
        } elseif ($problem -match '(?i)not found|does not exist|no such file') {
            'vanished-source'
        } elseif ($problem -match '(?i)input/output|i/o error|device error|disk') {
            'io-error'
        } else { 'other' }
        # The fingerprint lets us correlate repeated unreadable paths without
        # leaking personal project names or credentials through public logs.
        $fingerprint = 'unknown'
        if ($null -ne $item.PSObject.Properties['item'] -and
            -not [string]::IsNullOrWhiteSpace([string]$item.item)) {
            $bytes = [Text.Encoding]::UTF8.GetBytes(([string]$item.item).ToLowerInvariant())
            $digest = [Security.Cryptography.SHA256]::HashData($bytes)
            $fingerprint = [Convert]::ToHexString($digest).Substring(0,12)
        }
        $examples.Add("source-error category=$category fingerprint=$fingerprint") | Out-Null
    }
    Write-Output "Restic exit $ExitCode; reported source errors=$errorsFound (up to 8 sanitized examples follow)."
    foreach ($example in $examples) { Write-Output $example }
    if ($errorsFound -eq 0) {
        Write-Output 'No structured per-source error events were captured; root cause remains unknown.'
    }
}
