# Sanitized restic diagnostic falsification: never leak raw user paths
# or tokens in a public GitHub Actions log.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\restic-diagnostics.ps1')
$private = 'D:\Personal Project\provider-token-secret-file.txt'
$sample = '{"message_type":"error","item":"'+$private.Replace('\','\\')+'","during":"open","error":"Access is denied"}'
$lines = @($sample,'{"message_type":"summary","snapshot_id":"partial"}')
$out = @(Get-DevBoxResticErrorDiagnostics -Lines $lines -ExitCode 3) -join "`n"
if ($out -notmatch 'source errors=1' -or $out -notmatch 'category=permission' -or $out -notmatch 'fingerprint=[A-F0-9]{12}') {
    throw "Structured error was not classified as permission denied."
}
if ($out -match 'Personal Project|provider-token|Access is denied') {
    throw 'Sensitive path or raw error escaped into public diagnostic output.'
}
$other = @(Get-DevBoxResticErrorDiagnostics -Lines @('not json') -ExitCode 3) -join "`n"
if ($other -notmatch 'root cause remains unknown') {
    throw 'Unclassified Restic error was falsely diagnosed.'
}
Write-Output 'SANITIZED RESTIC EXIT 3 DIAGNOSTICS: PASS'
