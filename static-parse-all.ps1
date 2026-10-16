# static-parse-all.ps1 - Phase 52 static gate: AST-parse every .ps1 in the repo.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$bad = 0
Get-ChildItem $root -Recurse -Include *.ps1 -File | ForEach-Object {
    $tokens = $null; $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    if ($errors.Count) {
        $bad++
        Write-Output ("PS FAIL  " + $_.FullName)
        foreach ($e in $errors) { Write-Output ("    err: " + $e.Message + " @line " + $e.Extent.StartLineNumber) }
    } else {
        Write-Output ("PS OK    " + $_.FullName.Substring($root.Length + 1))
    }
}
if ($bad) { Write-Output ("PARSE RESULT: $bad broken file(s)"); exit 1 }
Write-Output "PARSE RESULT: all scripts parse cleanly"
exit 0
