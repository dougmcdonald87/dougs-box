# READ-ONLY Lenovo storage preflight for DevBox.
# Does not install, stop, start, reconfigure, tag, or create anything.
# Does not read credentials or mutate Tailscale, OpenCode, RustDesk, or shares.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
function Show-Check([string]$Name, [string]$Status, [string]$Detail) {
    Write-Output ("{0,-26} {1,-8} {2}" -f $Name, $Status, $Detail)
}
Write-Output 'DEVBOX LENOVO PREFLIGHT — READ-ONLY'
Write-Output ('Checked at UTC: ' + [DateTime]::UtcNow.ToString('o'))
try {
    $cmd = Get-Command tailscale -ErrorAction Stop
    $svc = Get-Service -Name Tailscale -ErrorAction Stop
    Show-Check 'Tailscale installed' 'PASS' ('Executable: ' + $cmd.Name)
    Show-Check 'Tailscale service' $(if ($svc.Status -eq 'Running') { 'PASS' } else { 'FAIL' }) ([string]$svc.Status)
    $ips = @(& $cmd.Source ip -4)
    $ip = ($ips | Where-Object { $_ -match '^100\.\d+\.\d+\.\d+$' } | Select-Object -First 1)
    Show-Check 'Tailnet IPv4' $(if ($ip) { 'PASS' } else { 'FAIL' }) ([string]$ip)
    Show-Check 'Expected Lenovo IP' $(if ($ip -eq '100.70.202.110') { 'PASS' } else { 'VERIFY' }) 'Expected 100.70.202.110'
} catch {
    Show-Check 'Tailscale' 'FAIL' $_.Exception.Message
}
try {
    $listeners = @(Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue)
    if ($listeners.Count -eq 0) {
        Show-Check 'TCP 8000 listener' 'FREE' 'No process listening; isolated DevBox service might use this port.'
    } else {
        foreach ($listener in $listeners) {
            $ownerProcess = Get-Process -Id $listener.OwningProcess -ErrorAction SilentlyContinue
            Show-Check 'TCP 8000 listener' 'IN USE' ("{0}:{1} — process: {2} (PID {3})" -f $listener.LocalAddress,$listener.LocalPort,$ownerProcess.ProcessName,$listener.OwningProcess)
        }
    }
} catch {
    Show-Check 'TCP 8000 listener' 'UNKNOWN' $_.Exception.Message
}
try {
    $task = Get-ScheduledTask -TaskName 'DevBox-RestServer' -ErrorAction SilentlyContinue
    Show-Check 'Dedicated boot task' $(if ($task) { 'EXISTS' } else { 'ABSENT' }) 'DevBox-RestServer'
} catch {
    Show-Check 'Dedicated boot task' 'UNKNOWN' $_.Exception.Message
}
try {
    $configPath = 'C:\DevBox-Storage\rest-server\storage-host-state.json'
    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        $state = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        Show-Check 'DevBox storage config' 'EXISTS' ("Data path: {0}; Port: {1}" -f $state.dataPath,$state.port)
    } else {
        Show-Check 'DevBox storage config' 'ABSENT' 'No dedicated storage state file.'
    }
} catch {
    Show-Check 'DevBox storage config' 'UNKNOWN' $_.Exception.Message
}
try {
    foreach ($disk in (Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3')) {
        $free = [math]::Round([double]$disk.FreeSpace/1GB,1)
        Show-Check ('Local drive ' + $disk.DeviceID) 'READ' ("Free: $free GiB (approx); no files created")
    }
} catch {
    Show-Check 'Local drive capacity' 'UNKNOWN' $_.Exception.Message
}
try {
    $shareNames = @(Get-SmbShare -ErrorAction Stop | Where-Object {$_.Special -eq $false} | ForEach-Object {$_.Name})
    Show-Check 'Existing SMB share names' 'READ' ($shareNames -join ', ')
} catch {
    Show-Check 'SMB share inventory' 'UNKNOWN' $_.Exception.Message
}
Write-Output 'END OF READ-ONLY PREFLIGHT — no changes made.'
