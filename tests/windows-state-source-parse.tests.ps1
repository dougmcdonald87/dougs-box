$ErrorActionPreference='Stop'
$root=Join-Path $PSScriptRoot '../scripts'
$failures=@()
foreach($name in @('windows-state-checkpoint.ps1','windows-state-operator.ps1','windows-state-roundtrip.ps1')){
    $tokens=$null;$errors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $name),[ref]$tokens,[ref]$errors)
    foreach($error in $errors){$failures+=($name+': '+$error.Message)}
}
if($failures.Count){throw ($failures -join "`n")}
Write-Output 'WINDOWS STATE DEPENDENCY PARSE: PASS'
